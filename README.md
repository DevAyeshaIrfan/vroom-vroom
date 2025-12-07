# VROOM VROOM 🏎️  
_A Racecar Game in x86 Assembly_

VROOM VROOM is a 16-bit racecar game written entirely in x86 Assembly.  
It runs in DOS (or DOSBox) using VGA graphics mode and shows how far low-level programming can go in building a fully animated, interactive game with music and multitasking.

---

## 🎮 Gameplay Overview

You control a **red racecar** driving down a three-lane road:

- **Avoid blue obstacle cars**
- **Collect coins** to increase your score
- **Manage your fuel bar** before it runs out
- **Pause and resume** the game any time
- Experience **smooth animations**, **sparks on collision**, and **background music** implemented via multitasking.

You lose if:
- You **collide** with an obstacle car, or  
- Your **fuel bar empties**.

At the end, you’ll see your **final score** along with a clean exit back to DOS.

---

## ✨ Features

### User Interface & Flow
1. **Introduction Screen** – Title and developer credits.
2. **Instruction Screen** – Explains controls and gameplay rules.
3. **Get/Save Player Details** – Prompts for and stores player name and roll number.
4. **Main Screen (Static)** – Road, lanes, and UI elements before the game starts.
5. **“Press Any Key to Start” Prompt** – Game waits for user input to begin.
6. **Game Start on Key Press** – All animations and game logic begin on key press.
19. **Ending Message Screen** – Custom message after game over / end state.
20. **Ending Screen** – Final screen summarizing the session.
21. **End Score** – Displays the total score collected during the run.
22. **Exit from Game** – Clean, controlled exit sequence.
23. **Black Screen with DOSBox Cursor** – Control returned safely to DOS.
24. **Run → Pause → Exit Flow Supported**
25. **Run → Empty Fuel → Exit Flow Supported**

### Gameplay Mechanics
7. **Animated Obstacle Cars, Coins, and Fuel Icons**
8. **Random Placement on One of Three Lanes** – All moving elements appear only in valid lanes.
9. **Red Car Movement in All Four Directions** – Left, right, up, and down controls.
10. **No Overlapping of Obstacles, Fuel, and Coins** – Objects are spawned with collision-free placement rules.
11. **Obstacle Cars Fade In / Fade Out** – Visual effect as cars appear/disappear.
12. **Score Increases When Obstacle Cars Fade Out** – Reward for successfully avoiding obstacles.
13. **Fuel Bar Decreases Over Time** – Time-based challenge, not just obstacle avoidance.
17. **Collision Detection** – Detects when the red car hits an obstacle.
18. **Spark Effect on Collision** – Visual feedback for a crash.

### Control & System Features
14. **Pause Functionality** – Temporarily stop game animation and logic.
15. **Confirmation Screen** – Appears on ESC or exit attempts (e.g., “Are you sure?”).
16. **Resume Functionality** – Continue game after pause/confirmation.
26. **Stack Clearance & Unhooking** – Proper cleanup of stack and interrupt handlers.
27. **Music Implemented Using Multitasking** – Background music runs via interrupts alongside the game loop.

---

## ⌨️ Controls

> You can adjust this section to match your exact key mappings.

- **Arrow Keys** – Move the red car:
  - **Left / Right**: Change lanes
  - **Up / Down**: Fine-tune position along the road
- **ESC** – Open confirmation dialog to pause/exit
- **Any Key (at intro/main screen)** – Start the game

---




