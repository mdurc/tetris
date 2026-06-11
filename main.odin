package main

import "core:fmt"
import rl "vendor:raylib"

SCREEN_WIDTH, SCREEN_HEIGHT :: 1200, 1000
BG_COLOR :: rl.Color{0x28, 0x29, 0x23, 0xFF}

GRID_SIZE :: 40  // pixels
GAME_WIDTH :: 10 // # of grid spaces
GAME_HEIGHT :: GAME_WIDTH * 2

Tetromino :: enum { I, J, L, O, S, T, Z }
tetrominoColor : [Tetromino]rl.Color = {
  .I = rl.Color{0x66, 0xAB, 0xAA, 0xFF}, // cyan
  .J = rl.Color{0x5C, 0x74, 0xA1, 0xFF}, // blue
  .L = rl.Color{0xC7, 0x7D, 0x51, 0xFF}, // orange
  .O = rl.Color{0xC5, 0xB6, 0x65, 0xFF}, // yellow
  .S = rl.Color{0x7D, 0x9F, 0x64, 0xFF}, // green
  .T = rl.Color{0x91, 0x72, 0x9B, 0xFF}, // purple
  .Z = rl.Color{0xBE, 0x61, 0x5B, 0xFF}, // red
}

State :: struct {
  cur, hold : Tetromino,
  next : [3]Tetromino,
  lines, level, score : int,
}

/*
   -- https://tetris.wiki/Random_Generator
   Tetromino randomization is done by drawing each of the 7 pieces randomly from a bag.
   No more than 12 tetrominoes can be produced between one I piece and the next.
   Runs of S and Z tetrominoes are limited to a length of 4.
   First piece of the first bag is always I, J, L, or T.
*/

render_game_wireframe :: proc() {
  // c.int == i32
  dx, dy :: GRID_SIZE, GRID_SIZE
  width, height : i32 = dx*GAME_WIDTH, dy*GAME_HEIGHT
  sx : i32 = (SCREEN_WIDTH-width) >> 1
  sy : i32 = (SCREEN_HEIGHT-height) >> 1

  // rl.DrawRectangleLines(x, y, width, height, rl.DARKGRAY) // too thin
  // r := rl.Rectangle{f32(x), f32(y), f32(width), f32(height)}
  // rl.DrawRectangleLinesEx(r, 2, rl.DARKGRAY)
  x, y : i32
  for x = 0; x < GAME_WIDTH + 1; x += 1 {
    rl.DrawLine(sx+x*dx, sy, sx+x*dx, sy+height, rl.DARKGRAY)
  }
  for y = 0; y < GAME_HEIGHT + 1; y += 1 {
    rl.DrawLine(sx, sy+y*dy, sx+width, sy+y*dy, rl.DARKGRAY)
    for x = 0; x < GAME_WIDTH + 1; x += 1 {
      rl.DrawCircleV(rl.Vector2{f32(sx+x*dx)-0.25, f32(sy+y*dy)-0.25}, 1.25, rl.DARKGRAY)
    }
  }

  // render next tetrominos frame
  rl.DrawRectangleLines(sx+width+1.5*dx, sy+dy, 6*dx, 9*dy, rl.DARKGRAY)

  // render hold tetromino frame
  rl.DrawRectangleLines(sx-1.5*dx, sy+dy, -6*dx, 5*dy, rl.DARKGRAY)

  // render score frame
  rl.DrawRectangleLines(sx-1.5*dx, sy+height-dy, -6*dx, -7*dy, rl.DARKGRAY)
}

main :: proc() {
  rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "tetris")
  defer rl.CloseWindow()

  g := rl.LoadTexture("res/grid.png")

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)

    x : i32
    for &c, i in tetrominoColor {
      rl.DrawTexture(g, i32(400+i32(i)*40), 100, c)
    }
    render_game_wireframe()

    rl.EndDrawing()
  }
}
