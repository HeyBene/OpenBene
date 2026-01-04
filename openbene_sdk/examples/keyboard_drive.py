#!/usr/bin/env python3
"""
OpenBene Keyboard Control

Interactive keyboard control for OpenBene robots using WASD keys.
This is a simple terminal-based controller for manual robot operation.

Controls:
    W - Move forward
    S - Move backward
    A - Turn left
    D - Turn right
    SPACE - Stop
    Q - Quit

Requirements:
    - OpenBene robot on same WiFi network
    - Terminal that supports input() (standard Python console)
"""

from openbene import OpenBene
import sys
import time


class KeyboardController:
    """
    Terminal-based keyboard controller for OpenBene robot

    Uses simple input() for cross-platform compatibility.
    For more advanced control, consider using libraries like 'pynput' or 'keyboard'.
    """

    def __init__(self, bot, speed=0.6):
        """
        Initialize keyboard controller

        Args:
            bot (OpenBene): Connected robot instance
            speed (float): Default movement speed (0.0 to 1.0)
        """
        self.bot = bot
        self.speed = speed
        self.running = False

    def print_instructions(self):
        """Display control instructions"""
        print("\n" + "=" * 60)
        print("Keyboard Control Active")
        print("=" * 60)
        print("\nControls:")
        print("  W - Move Forward")
        print("  S - Move Backward")
        print("  A - Turn Left")
        print("  D - Turn Right")
        print("  SPACE - Stop")
        print("  + - Increase Speed")
        print("  - - Decrease Speed")
        print("  Q - Quit")
        print("\n" + "=" * 60)
        print(f"Current Speed: {int(self.speed * 100)}%")
        print("=" * 60 + "\n")

    def handle_command(self, key):
        """
        Process keyboard input and send robot commands

        Args:
            key (str): Key pressed by user

        Returns:
            bool: True to continue, False to quit
        """
        key = key.strip().lower()

        if key == 'w':
            print(f"→ Forward ({int(self.speed * 100)}%)")
            self.bot.move_forward(self.speed)

        elif key == 's':
            print(f"← Backward ({int(self.speed * 100)}%)")
            self.bot.move_backward(self.speed)

        elif key == 'a':
            print(f"↺ Turn Left ({int(self.speed * 100)}%)")
            self.bot.turn_left(self.speed)

        elif key == 'd':
            print(f"↻ Turn Right ({int(self.speed * 100)}%)")
            self.bot.turn_right(self.speed)

        elif key == ' ' or key == '':
            print("■ Stop")
            self.bot.stop()

        elif key == '+' or key == '=':
            self.speed = min(1.0, self.speed + 0.1)
            print(f"Speed increased to {int(self.speed * 100)}%")
            self.bot.stop()

        elif key == '-' or key == '_':
            self.speed = max(0.1, self.speed - 0.1)
            print(f"Speed decreased to {int(self.speed * 100)}%")
            self.bot.stop()

        elif key == 'q':
            print("\nQuitting...")
            self.bot.stop()
            return False

        else:
            print(f"Unknown command: '{key}' (Use W/A/S/D/SPACE/Q)")

        return True

    def run(self):
        """Start the keyboard control loop"""
        self.print_instructions()
        self.running = True

        try:
            while self.running:
                # Simple input-based control
                key = input("Command> ")
                if not self.handle_command(key):
                    break

        except KeyboardInterrupt:
            print("\n\nInterrupted by user")
            self.bot.stop()

        except Exception as e:
            print(f"\nError: {e}")
            self.bot.stop()

        finally:
            self.running = False
            print("\nKeyboard control stopped")


def simple_control_mode():
    """
    Simple control mode using basic input()

    This is the most compatible mode that works everywhere.
    """
    print("\n" + "=" * 60)
    print("Simple Control Mode")
    print("=" * 60)
    print("\nType commands and press Enter:")
    print("  W/A/S/D - Movement")
    print("  SPACE - Stop")
    print("  Q - Quit\n")

    try:
        # Connect to robot
        print("Connecting to robot...")
        with OpenBene.connect_auto(timeout=10) as bot:
            print(f"✓ Connected to {bot.ip}\n")

            # Start keyboard controller
            controller = KeyboardController(bot, speed=0.6)
            controller.run()

    except Exception as e:
        print(f"\n✗ Connection failed: {e}")
        print("\nMake sure robot is running and connected to WiFi")


def advanced_control_mode():
    """
    Advanced control mode with real-time key detection

    Requires 'pynput' library for better control experience.
    Install with: pip install pynput
    """
    try:
        from pynput import keyboard
    except ImportError:
        print("\n✗ Advanced mode requires 'pynput' library")
        print("\nInstall with:")
        print("  pip install pynput")
        print("\nFalling back to simple mode...")
        time.sleep(2)
        simple_control_mode()
        return

    print("\n" + "=" * 60)
    print("Advanced Control Mode (Real-time)")
    print("=" * 60)
    print("\nHold down keys for continuous movement:")
    print("  W/A/S/D - Movement (hold to continue)")
    print("  ESC - Quit\n")

    current_bot = None
    active_command = None

    def on_press(key):
        """Handle key press events"""
        nonlocal active_command

        if current_bot is None:
            return

        try:
            if hasattr(key, 'char'):
                k = key.char.lower()

                if k == 'w' and active_command != 'w':
                    print("→ Forward")
                    current_bot.move_forward(0.6)
                    active_command = 'w'

                elif k == 's' and active_command != 's':
                    print("← Backward")
                    current_bot.move_backward(0.6)
                    active_command = 's'

                elif k == 'a' and active_command != 'a':
                    print("↺ Turn Left")
                    current_bot.turn_left(0.5)
                    active_command = 'a'

                elif k == 'd' and active_command != 'd':
                    print("↻ Turn Right")
                    current_bot.turn_right(0.5)
                    active_command = 'd'

        except AttributeError:
            pass

    def on_release(key):
        """Handle key release events"""
        nonlocal active_command

        if current_bot is None:
            return

        # Stop on key release
        if active_command is not None:
            print("■ Stop")
            current_bot.stop()
            active_command = None

        # Quit on ESC
        if key == keyboard.Key.esc:
            print("\nQuitting...")
            return False

    try:
        # Connect to robot
        print("Connecting to robot...")
        with OpenBene.connect_auto(timeout=10) as bot:
            current_bot = bot
            print(f"✓ Connected to {bot.ip}\n")
            print("Ready! Use W/A/S/D keys. Press ESC to quit.\n")

            # Start listening for key events
            with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
                listener.join()

    except Exception as e:
        print(f"\n✗ Error: {e}")

    finally:
        if current_bot:
            current_bot.stop()


def main():
    """Main entry point for keyboard control"""
    print("\n" + "=" * 60)
    print("OpenBene SDK - Keyboard Control")
    print("=" * 60)

    print("\nSelect control mode:\n")
    print("1. Simple Mode (works everywhere)")
    print("2. Advanced Mode (requires pynput library)")
    print("3. Exit\n")

    choice = input("Choice [1]: ").strip()

    if choice == '2':
        advanced_control_mode()
    elif choice == '3':
        print("Goodbye!")
    else:
        # Default to simple mode
        simple_control_mode()

    print("\n" + "=" * 60)
    print("Thanks for using OpenBene!")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
