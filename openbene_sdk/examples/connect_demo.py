#!/usr/bin/env python3
"""
OpenBene Connection Demo

This example demonstrates how to discover and connect to OpenBene robots
on your local network using UDP broadcast discovery.

Requirements:
    - OpenBene robot running on the same WiFi network
    - Robot app started and broadcasting
"""

from openbene import Discovery, OpenBene
import time


def manual_discovery_example():
    """
    Example 1: Manual discovery with callback

    Listen for robot broadcasts and print discovered robots.
    """
    print("=" * 60)
    print("Example 1: Manual Discovery")
    print("=" * 60)

    discovered_robots = []

    def on_robot_discovered(robot_info):
        """Callback function when a robot is discovered"""
        name = robot_info.get('name', 'Unknown')
        ip = robot_info.get('ip', 'Unknown')
        print(f"✓ Found robot: {name} at {ip}")
        discovered_robots.append(robot_info)

    # Create discovery instance
    discovery = Discovery(port=12345)

    # Start listening for broadcasts
    print("\nListening for robot broadcasts...")
    print("Make sure your robot app is running and click 'Start Robot'\n")

    discovery.start(on_discovery=on_robot_discovered)

    # Listen for 10 seconds
    try:
        time.sleep(10)
    except KeyboardInterrupt:
        print("\nDiscovery interrupted by user")

    # Stop discovery
    discovery.stop()

    print(f"\nDiscovery complete. Found {len(discovered_robots)} robot(s).")
    print()


def auto_connect_example():
    """
    Example 2: Automatic connection

    Automatically discover and connect to the first available robot.
    """
    print("=" * 60)
    print("Example 2: Auto-Connect")
    print("=" * 60)

    try:
        print("\nSearching for robots...")

        # Auto-discover and connect (10 second timeout)
        bot = OpenBene.connect_auto(timeout=10)

        print(f"✓ Connected to robot at {bot.ip}")
        print(f"  Status: {bot}")

        # Test connection with a simple command
        print("\nTesting connection...")
        bot.stop()
        print("✓ Connection verified!")

        # Disconnect
        bot.disconnect()
        print("✓ Disconnected successfully")

    except Exception as e:
        print(f"✗ Connection failed: {e}")
        print("\nTroubleshooting:")
        print("  1. Make sure robot app is running")
        print("  2. Check WiFi connection")
        print("  3. Verify both devices are on same network")

    print()


def manual_connect_example():
    """
    Example 3: Manual connection with known IP

    Connect directly if you already know the robot's IP address.
    """
    print("=" * 60)
    print("Example 3: Manual Connection")
    print("=" * 60)

    # Replace with your robot's actual IP
    robot_ip = "192.168.1.100"

    print(f"\nAttempting to connect to {robot_ip}...")

    try:
        bot = OpenBene(robot_ip)
        bot.connect(timeout=5)

        print(f"✓ Connected to robot at {bot.ip}")
        print(f"  Status: {bot}")

        # Send test command
        bot.stop()
        print("✓ Connection verified!")

        # Clean disconnect
        bot.disconnect()
        print("✓ Disconnected successfully")

    except Exception as e:
        print(f"✗ Connection failed: {e}")
        print(f"\nMake sure robot is running at {robot_ip}")

    print()


def context_manager_example():
    """
    Example 4: Using context manager for auto-cleanup

    Best practice: Use 'with' statement for automatic resource management.
    """
    print("=" * 60)
    print("Example 4: Context Manager (Recommended)")
    print("=" * 60)

    try:
        print("\nConnecting to robot...")

        # Context manager automatically handles disconnect
        with OpenBene.connect_auto(timeout=10) as bot:
            print(f"✓ Connected to {bot.ip}")

            # Your robot control code here
            bot.stop()
            print("✓ Robot ready for commands")

            # No need to call disconnect() - it's automatic!

        print("✓ Disconnected automatically")

    except Exception as e:
        print(f"✗ Connection failed: {e}")

    print()


def main():
    """Run all connection examples"""
    print("\n" + "=" * 60)
    print("OpenBene SDK - Connection Examples")
    print("=" * 60)
    print()

    print("This demo will show you different ways to connect to your robot.")
    print("Press Ctrl+C at any time to skip an example.\n")

    try:
        # Run examples
        manual_discovery_example()
        input("Press Enter to continue to next example...")

        auto_connect_example()
        input("Press Enter to continue to next example...")

        manual_connect_example()
        input("Press Enter to continue to next example...")

        context_manager_example()

    except KeyboardInterrupt:
        print("\n\nDemo interrupted by user.")

    print("=" * 60)
    print("Demo complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("  - Try control_demo.py for movement examples")
    print("  - Try keyboard_drive.py for interactive control")
    print()


if __name__ == "__main__":
    main()
