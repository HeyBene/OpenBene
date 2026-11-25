#ifndef OBZ_ZENOH_H
#define OBZ_ZENOH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque zenoh-pico session owned by the bridge.
typedef struct obz_session obz_session_t;

/// Delivers one sample. `key` and `payload` are borrowed and only valid for
/// the duration of the call; copy them if they outlive the callback.
typedef void (*obz_sample_cb)(const char *key, const uint8_t *payload, size_t len, void *ctx);

/// Opens a session. `mode` is `client` or `peer`; `endpoint` is a normalized
/// locator such as `tcp/192.168.1.20:7447`. Returns NULL on failure and writes a
/// short message into `err` when provided.
obz_session_t *obz_open_session(const char *endpoint,
                                const char *mode,
                                char *err,
                                size_t err_len);

void obz_close_session(obz_session_t *session);

int obz_session_is_open(obz_session_t *session);

/// Blocking put with drop-on-congestion so a stalled receiver cannot wedge the
/// app. Returns 0 on success, negative on failure.
int obz_put(obz_session_t *session,
            const char *key,
            const uint8_t *data,
            size_t len);

/// Declares a subscriber. Returns a positive subscription id, or 0 on failure.
uint64_t obz_subscribe(obz_session_t *session,
                       const char *key,
                       obz_sample_cb cb,
                       void *ctx);

/// Removes a subscription. Returns 0 when the id was found.
int obz_unsubscribe(obz_session_t *session, uint64_t id);

/// Returns the compiled zenoh-pico version string (static storage).
const char *obz_version(void);

#ifdef __cplusplus
}
#endif

#endif /* OBZ_ZENOH_H */
