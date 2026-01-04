#!/usr/bin/env python3
"""
OpenBene Control Demo

This example demonstrates various robot movement patterns and control sequences.
Shows how to use the OpenBene API for basic navigation.

Requirements:
    - OpenBene robot connected to WiFi
    - Sufficient space for robot to move safely
"""

from openbene import OpenBene
import time


def basic_movements(bot):
    """
    Demonstrate basic movement commands

    Shows: move_forward, move_backward, turn_left, turn_right, stop
    """
    print("\n" + "=" * 60)
    print("Demo 1: Basic Movements")
    print("=" * 60)

    print("\n→ Moving forward (50% speed)...")
    bot.move_forward(0.5)
    time.sleep(2)
    bot.stop()
    time.sleep(1)

    print("→ Moving backward (50% speed)...")
    bot.move_backward(0.5)
    time.sleep(2)
    bot.stop()
    time.sleep(1)

    print("→ Turning left (30% speed)...")
    bot.turn_left(0.3)
    time.sleep(1.5)
    bot.stop()
    time.sleep(1)

    print("→ Turning right (30% speed)...")
    bot.turn_right(0.3)
    time.sleep(1.5)
    bot.stop()

    print("✓ Basic movements complete!\n")


def square_pattern(bot):
    """
    Drive the robot in a square pattern

    Demonstrates: Combining forward movement with turns
    """
    print("\n" + "=" * 60)
    print("Demo 2: Square Pattern")
    print("=" * 60)

    print("\nDriving in a square pattern...\n")

    for i in range(4):
        print(f"  Side {i + 1}/4...")

        # Move forward
        bot.move_forward(0.6)
        time.sleep(2)
        bot.stop()
        time.sleep(0.5)

        # Turn 90 degrees right
        bot.turn_right(0.4)
        time.sleep(1)
        bot.stop()
        time.sleep(0.5)

    print("✓ Square pattern complete!\n")


def figure_eight(bot):
    """
    Drive the robot in a figure-8 pattern

    Demonstrates: Differential drive control for curved paths
    """
    print("\n" + "=" * 60)
    print("Demo 3: Figure-8 Pattern")
    print("=" * 60)

    print("\nDriving in a figure-8 pattern...\n")

    # First circle (clockwise)
    print("  Circle 1 (right turn)...")
    bot.drive(0.7, 0.3)  # Right wheel slower = turn right
    time.sleep(4)
    bot.stop()
    time.sleep(0.5)

    # Second circle (counter-clockwise)
    print("  Circle 2 (left turn)...")
    bot.drive(0.3, 0.7)  # Left wheel slower = turn left
    time.sleep(4)
    bot.stop()

    print("✓ Figure-8 complete!\n")


def precision_control(bot):
    """
    Demonstrate fine-grained motor control

    Shows: Using drive() method directly for differential steering
    """
    print("\n" + "=" * 60)
    print("Demo 4: Precision Control")
    print("=" * 60)

    print("\nDemonstrating differential drive control...\n")

    # Gradual acceleration
    print("  Gradual acceleration...")
    for speed in [0.2, 0.4, 0.6, 0.8]:
        print(f"    Speed: {speed}")
        bot.drive(speed, speed)
        time.sleep(1)
    bot.stop()
    time.sleep(1)

    # Gradual turning
    print("  Smooth curved turn...")
    bot.drive(0.8, 0.4)  # Gentle right curve
    time.sleep(3)
    bot.stop()
    time.sleep(1)

    # Sharp pivot
    print("  Sharp 180° pivot...")
    bot.drive(0.5, -0.5)  # Counter-rotating wheels
    time.sleep(2)
    bot.stop()

    print("✓ Precision control complete!\n")


def speed_test(bot):
    """
    Test different speed levels

    Demonstrates: Speed control from slow to fast
    """
    print("\n" + "=" * 60)
    print("Demo 5: Speed Test")
    print("=" * 60)

    print("\nTesting different speeds...\n")

    speeds = [
        (0.2, "Slow"),
        (0.5, "Medium"),
        (0.8, "Fast"),
        (1.0, "Full Speed"),
    ]

    for speed, label in speeds:
        print(f"  {label} ({int(speed * 100)}%)...")
        bot.move_forward(speed)
        time.sleep(1.5)
        bot.stop()
        time.sleep(0.5)

    print("✓ Speed test complete!\n")


def obstacle_avoidance_demo(bot):
    """
    Simple obstacle avoidance pattern

    Demonstrates: Combining movements for basic navigation logic
    Note: This is just a demo pattern - real obstacle detection
          requires sensors (coming in Milestone 2)
    """
    print("\n" + "=" * 60)
    print("Demo 6: Obstacle Avoidance Pattern")
    print("=" * 60)

    print("\nSimulating obstacle avoidance (no sensors, just pattern)...\n")

    for i in range(3):
        print(f"  Iteration {i + 1}/3...")

        # Move forward
        print("    → Moving forward...")
        bot.move_forward(0.5)
        time.sleep(2)
        bot.stop()
        time.sleep(0.5)

        # "Detect obstacle" - back up
        print("    ← Backing up...")
        bot.move_backward(0.4)
        time.sleep(1)
        bot.stop()
        time.sleep(0.5)

        # Turn to avoid
        print("    ↻ Turning to avoid...")
        bot.turn_right(0.5)
        time.sleep(1)
        bot.stop()
        time.sleep(0.5)

    print("✓ Avoidance pattern complete!\n")


def main():
    """Run all control demonstrations"""
    print("\n" + "=" * 60)
    print("OpenBene SDK - Control Demonstrations")
    print("=" * 60)
    print()

    print("This demo will run various movement patterns.")
    print("Make sure your robot has enough space to move safely!")
    print("\nPress Ctrl+C at any time to stop.\n")

    input("Press Enter to connect to robot...")

    try:
        # Connect to robot
        print("\nConnecting to robot...")
        with OpenBene.connect_auto(timeout=10) as bot:
            print(f"✓ Connected to {bot.ip}\n")

            print("Starting demonstrations in 3 seconds...")
            time.sleep(3)

            # Run all demos
            basic_movements(bot)
            input("Press Enter for next demo (Square Pattern)...")

            square_pattern(bot)
            input("Press Enter for next demo (Figure-8)...")

            figure_eight(bot)
            input("Press Enter for next demo (Precision Control)...")

            precision_control(bot)
            input("Press Enter for next demo (Speed Test)...")

            speed_test(bot)
            input("Press Enter for final demo (Obstacle Avoidance)...")

            obstacle_avoidance_demo(bot)

            print("=" * 60)
            print("All demonstrations complete!")
            print("=" * 60)

    except KeyboardInterrupt:
        print("\n\nDemo interrupted by user.")
        print("Stopping robot...")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        print("\nMake sure:")
        print("  1. Robot is powered on")
        print("  2. Robot app is running")
        print("  3. Robot is on the same WiFi network")

    print("\nDisconnecting...")
    print("Done!\n")


if __name__ == "__main__":
    main()
