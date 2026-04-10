from __future__ import annotations

from typing import Optional, Sequence


CONFIGURE_TRANSITION_ID = 1
ACTIVATE_TRANSITION_ID = 3


def normalize_node_names(node_names: Sequence[str]) -> list[str]:
    normalized = [str(name).strip() for name in node_names if str(name).strip()]
    if not normalized:
        raise ValueError("managed_nodes must contain at least one non-empty node name.")
    return normalized


def main(args: Optional[list[str]] = None) -> None:
    import rclpy
    from lifecycle_msgs.srv import ChangeState, GetState
    from rcl_interfaces.msg import ParameterDescriptor
    from rclpy.node import Node

    class LifecycleBringup(Node):
        def __init__(self) -> None:
            super().__init__("openbene_lifecycle_bringup")

            self.declare_parameter(
                "managed_nodes",
                ["map_server"],
                ParameterDescriptor(description="Lifecycle nodes to configure and activate."),
            )
            self.declare_parameter("configure_timeout_sec", 8.0)
            self.declare_parameter("activate_timeout_sec", 8.0)

            self._managed_nodes = normalize_node_names(self.get_parameter("managed_nodes").value)
            self._configure_timeout_sec = float(self.get_parameter("configure_timeout_sec").value)
            self._activate_timeout_sec = float(self.get_parameter("activate_timeout_sec").value)

        def run(self) -> None:
            try:
                for node_name in self._managed_nodes:
                    self._transition_node(
                        node_name=node_name,
                        transition_id=CONFIGURE_TRANSITION_ID,
                        label="configure",
                        timeout_sec=self._configure_timeout_sec,
                    )
                    self._transition_node(
                        node_name=node_name,
                        transition_id=ACTIVATE_TRANSITION_ID,
                        label="activate",
                        timeout_sec=self._activate_timeout_sec,
                    )
                self.get_logger().info(
                    "Lifecycle bringup finished for: %s" % ", ".join(self._managed_nodes)
                )
            except Exception as exc:
                self.get_logger().error(f"Lifecycle bringup failed: {exc}")

        def _transition_node(
            self,
            *,
            node_name: str,
            transition_id: int,
            label: str,
            timeout_sec: float,
        ) -> None:
            service_prefix = node_name if node_name.startswith("/") else f"/{node_name}"
            change_state_service = f"{service_prefix}/change_state"
            get_state_service = f"{service_prefix}/get_state"

            state_client = self.create_client(GetState, get_state_service)
            if not state_client.wait_for_service(timeout_sec=timeout_sec):
                raise RuntimeError(f"Timed out waiting for service '{get_state_service}'.")

            client = self.create_client(ChangeState, change_state_service)
            if not client.wait_for_service(timeout_sec=timeout_sec):
                raise RuntimeError(f"Timed out waiting for service '{change_state_service}'.")

            request = ChangeState.Request()
            request.transition.id = transition_id
            future = client.call_async(request)
            rclpy.spin_until_future_complete(self, future, timeout_sec=timeout_sec)
            if not future.done() or future.result() is None:
                raise RuntimeError(f"Lifecycle transition '{label}' on '{node_name}' timed out.")
            if not future.result().success:
                raise RuntimeError(f"Lifecycle transition '{label}' on '{node_name}' was rejected.")

            state_future = state_client.call_async(GetState.Request())
            rclpy.spin_until_future_complete(self, state_future, timeout_sec=timeout_sec)
            state_label = "unknown"
            if state_future.done() and state_future.result() is not None:
                state_label = state_future.result().current_state.label

            self.get_logger().info(
                "Lifecycle transition '%s' succeeded on '%s'. Current state: %s"
                % (label, node_name, state_label)
            )

    rclpy.init(args=args)
    node = LifecycleBringup()
    try:
        node.run()
    except KeyboardInterrupt:
        pass
    finally:
        if rclpy.ok():
            node.destroy_node()
            rclpy.shutdown()
