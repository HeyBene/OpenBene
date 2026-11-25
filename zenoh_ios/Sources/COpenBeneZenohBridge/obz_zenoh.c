//
// obz_zenoh.c
// Thin C surface over zenoh-pico for the Swift OpenBeneZenohPico target.
//
// The API shape follows the bridge used by Beneros' swiftros app
// (open / put / subscribe / close), trimmed to what the OpenBene transport
// needs so the Swift side never touches zenoh-pico's move-only types.
//

#include "obz_zenoh.h"

#include <zenoh-pico.h>

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OBZ_MAX_SUBSCRIPTIONS 8

typedef struct {
    uint64_t id;
    obz_sample_cb callback;
    void *context;
    z_owned_subscriber_t subscriber;
    int active;
} obz_subscription_t;

struct obz_session {
    z_owned_session_t session;
    obz_subscription_t subscriptions[OBZ_MAX_SUBSCRIPTIONS];
    uint64_t next_id;
    pthread_mutex_t lock;
};

static void obz_set_error(char *err, size_t err_len, const char *message) {
    if (!err || err_len == 0) {
        return;
    }
    snprintf(err, err_len, "%s", message ? message : "unknown error");
}

static void obz_sample_handler(z_loaned_sample_t *sample, void *context) {
    obz_subscription_t *subscription = (obz_subscription_t *)context;
    if (!subscription || !subscription->callback) {
        return;
    }

    const z_loaned_keyexpr_t *keyexpr = z_sample_keyexpr(sample);
    z_view_string_t key_view;
    z_keyexpr_as_view_string(keyexpr, &key_view);
    const z_loaned_string_t *key_string = z_loan(key_view);
    size_t key_len = z_string_len(key_string);
    char *key = (char *)malloc(key_len + 1);
    if (!key) {
        return;
    }
    if (key_len > 0) {
        memcpy(key, z_string_data(key_string), key_len);
    }
    key[key_len] = '\0';

    const z_loaned_bytes_t *payload_bytes = z_sample_payload(sample);
    size_t payload_len = z_bytes_len(payload_bytes);
    uint8_t *payload = NULL;
    if (payload_len > 0) {
        payload = (uint8_t *)malloc(payload_len);
        if (payload) {
            z_bytes_reader_t reader = z_bytes_get_reader(payload_bytes);
            z_bytes_reader_read(&reader, payload, payload_len);
        } else {
            payload_len = 0;
        }
    }

    subscription->callback(key, payload, payload_len, subscription->context);

    free(payload);
    free(key);
}

obz_session_t *obz_open_session(const char *endpoint,
                                const char *mode,
                                char *err,
                                size_t err_len) {
    if (!endpoint || !mode) {
        obz_set_error(err, err_len, "endpoint and mode are required");
        return NULL;
    }

    obz_session_t *session = (obz_session_t *)calloc(1, sizeof(obz_session_t));
    if (!session) {
        obz_set_error(err, err_len, "out of memory");
        return NULL;
    }
    pthread_mutex_init(&session->lock, NULL);
    session->next_id = 1;

    z_owned_config_t config;
    if (z_config_default(&config) < 0) {
        obz_set_error(err, err_len, "z_config_default failed");
        pthread_mutex_destroy(&session->lock);
        free(session);
        return NULL;
    }
    if (zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, mode) < 0) {
        z_drop(z_move(config));
        obz_set_error(err, err_len, "invalid session mode");
        pthread_mutex_destroy(&session->lock);
        free(session);
        return NULL;
    }
    if (zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, endpoint) < 0) {
        z_drop(z_move(config));
        obz_set_error(err, err_len, "invalid endpoint");
        pthread_mutex_destroy(&session->lock);
        free(session);
        return NULL;
    }

    if (z_open(&session->session, z_move(config), NULL) < 0) {
        obz_set_error(err, err_len, "z_open failed (endpoint unreachable?)");
        pthread_mutex_destroy(&session->lock);
        free(session);
        return NULL;
    }

    // zenoh-pico only processes incoming samples while its read task runs.
    zp_start_read_task(z_loan_mut(session->session), NULL);
    zp_start_lease_task(z_loan_mut(session->session), NULL);
    return session;
}

void obz_close_session(obz_session_t *session) {
    if (!session) {
        return;
    }

    pthread_mutex_lock(&session->lock);
    for (size_t i = 0; i < OBZ_MAX_SUBSCRIPTIONS; i++) {
        if (session->subscriptions[i].active) {
            z_undeclare_subscriber(z_move(session->subscriptions[i].subscriber));
            session->subscriptions[i].active = 0;
        }
    }
    pthread_mutex_unlock(&session->lock);

    zp_stop_read_task(z_loan_mut(session->session));
    zp_stop_lease_task(z_loan_mut(session->session));
    z_close(z_loan_mut(session->session), NULL);
    z_drop(z_move(session->session));

    pthread_mutex_destroy(&session->lock);
    free(session);
}

int obz_session_is_open(obz_session_t *session) {
    if (!session) {
        return 0;
    }
    return !z_session_is_closed(z_loan(session->session));
}

int obz_put(obz_session_t *session,
            const char *key,
            const uint8_t *data,
            size_t len) {
    if (!session || !key) {
        return -1;
    }
    if (z_session_is_closed(z_loan(session->session))) {
        return -2;
    }

    z_view_keyexpr_t keyexpr;
    if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
        return -3;
    }

    z_owned_bytes_t bytes;
    // z_bytes_from_buf takes a mutable pointer but only copies from it.
    if (z_bytes_from_buf(&bytes, (uint8_t *)data, len, NULL, NULL) < 0) {
        return -4;
    }

    z_put_options_t options;
    z_put_options_default(&options);
    options.congestion_control = Z_CONGESTION_CONTROL_DROP;

    return z_put(z_loan(session->session), z_loan(keyexpr), z_move(bytes), &options);
}

uint64_t obz_subscribe(obz_session_t *session,
                       const char *key,
                       obz_sample_cb cb,
                       void *ctx) {
    if (!session || !key || !cb) {
        return 0;
    }

    z_view_keyexpr_t keyexpr;
    if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
        return 0;
    }

    pthread_mutex_lock(&session->lock);
    obz_subscription_t *slot = NULL;
    for (size_t i = 0; i < OBZ_MAX_SUBSCRIPTIONS; i++) {
        if (!session->subscriptions[i].active) {
            slot = &session->subscriptions[i];
            break;
        }
    }
    if (!slot) {
        pthread_mutex_unlock(&session->lock);
        return 0;
    }

    slot->id = session->next_id++;
    slot->callback = cb;
    slot->context = ctx;
    slot->active = 1;

    z_owned_closure_sample_t closure;
    z_closure(&closure, obz_sample_handler, NULL, slot);

    z_subscriber_options_t options;
    z_subscriber_options_default(&options);

    int result = z_declare_subscriber(z_loan(session->session), &slot->subscriber,
                                      z_loan(keyexpr), z_move(closure), &options);
    uint64_t id = slot->id;
    if (result < 0) {
        slot->active = 0;
        id = 0;
    }
    pthread_mutex_unlock(&session->lock);
    return id;
}

int obz_unsubscribe(obz_session_t *session, uint64_t id) {
    if (!session || id == 0) {
        return -1;
    }

    pthread_mutex_lock(&session->lock);
    for (size_t i = 0; i < OBZ_MAX_SUBSCRIPTIONS; i++) {
        if (session->subscriptions[i].active && session->subscriptions[i].id == id) {
            z_undeclare_subscriber(z_move(session->subscriptions[i].subscriber));
            session->subscriptions[i].active = 0;
            pthread_mutex_unlock(&session->lock);
            return 0;
        }
    }
    pthread_mutex_unlock(&session->lock);
    return -1;
}

const char *obz_version(void) {
    return ZENOH_PICO;
}
