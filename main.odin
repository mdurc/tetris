package main

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX :: 1200, 1000
BG_COLOR :: rl.Color{0x28, 0x29, 0x23, 0xFF}

GRID_SIZE :: 40  // pixels
GAME_WIDTH_UNITS :: 10 // # of grid spaces
GAME_HEIGHT_UNITS :: GAME_WIDTH_UNITS * 2
GAME_WIDTH_PX :: GRID_SIZE*GAME_WIDTH_UNITS
GAME_HEIGHT_PX :: GRID_SIZE*GAME_HEIGHT_UNITS
GAME_START_X :: (SCREEN_WIDTH_PX-GAME_WIDTH_PX) >> 1
GAME_START_Y :: (SCREEN_HEIGHT_PX-GAME_HEIGHT_PX) >> 1

// shorter renames
width, height :: GAME_WIDTH_PX, GAME_HEIGHT_PX
dm, sx, sy :: GRID_SIZE, GAME_START_X, GAME_START_Y

FALL_SPEED :: 1.0
SOFT_SPEED :: 10.0
SIDE_SPEED :: 15.0

TetrominoType :: enum { I, J, L, O, S, T, Z }
tetroColor : [TetrominoType]rl.Color = {
  .I = rl.Color{0x66, 0xAB, 0xAA, 0xFF}, // cyan
  .J = rl.Color{0x5C, 0x74, 0xA1, 0xFF}, // blue
  .L = rl.Color{0xC7, 0x7D, 0x51, 0xFF}, // orange
  .O = rl.Color{0xC5, 0xB6, 0x65, 0xFF}, // yellow
  .S = rl.Color{0x7D, 0x9F, 0x64, 0xFF}, // green
  .T = rl.Color{0x91, 0x72, 0x9B, 0xFF}, // purple
  .Z = rl.Color{0xBE, 0x61, 0x5B, 0xFF}, // red
}

Tetromino :: struct {
  type : TetrominoType,
  minos : [4][2]i32, // offsets from pos
  pos : [2]i32,
  accum_y, accum_x : f32
}
tetros : [TetrominoType]Tetromino = {
  .I = { type = .I, minos = {{0,-1},{1,-1},{2,-1},{3,-1}} },
  .J = { type = .J, minos = {{0,-2},{0,-1},{1,-1},{2,-1}} },
  .L = { type = .L, minos = {{0,-1},{1,-1},{2,-1},{2,-2}} },
  .O = { type = .O, minos = {{1,-1},{1,-2},{2,-2},{2,-1}} },
  .S = { type = .S, minos = {{0,-1},{1,-1},{1,-2},{2,-2}} },
  .T = { type = .T, minos = {{0,-1},{1,-1},{1,-2},{2,-1}} },
  .Z = { type = .Z, minos = {{0,-2},{1,-2},{1,-1},{2,-1}} },
}

State :: struct {
  cur, hold : Tetromino,
  has_held : bool,

  next : [3]Tetromino,

  bag : bit_set[TetrominoType],
  first_piece_drawn : bool,

  grid : [GAME_WIDTH_UNITS][GAME_HEIGHT_UNITS]bool,

  lines, level, score : i32,
}
state : State
mino_tex : rl.Texture2D

render_game_wireframe :: proc() {
  // rl.DrawRectangleLines(x, y, width, height, rl.DARKGRAY) // too thin
  // r := rl.Rectangle{f32(x), f32(y), f32(width), f32(height)}
  // rl.DrawRectangleLinesEx(r, 2, rl.DARKGRAY)
  x, y : i32
  for x = 0; x < GAME_WIDTH_UNITS + 1; x += 1 {
    rl.DrawLine(sx+x*dm, sy, sx+x*dm, sy+height, rl.DARKGRAY)
  }
  for y = 0; y < GAME_HEIGHT_UNITS + 1; y += 1 {
    rl.DrawLine(sx, sy+y*dm, sx+width, sy+y*dm, rl.DARKGRAY)
    for x = 0; x < GAME_WIDTH_UNITS + 1; x += 1 {
      rl.DrawCircleV(rl.Vector2{f32(sx+x*dm)-0.25, f32(sy+y*dm)-0.25}, 1.25, rl.DARKGRAY)
    }
  }

  // render next tetrominos frame
  rl.DrawRectangleLines(sx+width+1.5*dm, sy+dm, 6*dm, 9*dm, rl.DARKGRAY)

  // render hold tetromino frame
  rl.DrawRectangleLines(sx-1.5*dm, sy+dm, -6*dm, 5*dm, rl.DARKGRAY)

  // render score frame
  rl.DrawRectangleLines(sx-1.5*dm, sy+height-dm, -6*dm, -7*dm, rl.DARKGRAY)
}

render_mino :: proc(x, y: i32, c: rl.Color) {
  rl.DrawTexture(mino_tex, sx+x*dm, sy+y*dm, c)
}

render_tetromino :: proc(t: ^Tetromino) {
  for &p in t.minos {
    // y+1 to account for the starting mino y position at -1
    render_mino(t.pos.x+p.x, (t.pos.y+1)+p.y, tetroColor[t.type])
  }
  when ODIN_DEBUG {
    sz : f32 = t.type == .I ? 4*dm: t.type == .O ? 2*dm: 3*dm
    rl.DrawRectangleLinesEx({f32(sx+t.pos.x*dm), f32(sy+(t.pos.y-1)*dm), sz, sz}, 3, rl.DARKPURPLE)
  }
}

tick :: proc(t: ^Tetromino, dt: f32) {
  t.accum_y += FALL_SPEED*dt
  dy, dx := i32(t.accum_y), i32(t.accum_x)
  t.accum_y -= f32(dy)
  if dy > 0 {
    t.pos.y += dy
  }
  if dx != 0 {
    t.pos.x += dx
  }
  if (t.accum_x < 0) == (dx < 0) {
    t.accum_x -= f32(dx)
  } else {
    t.accum_x += f32(dx)
  }
}

rotate_clockwise :: proc(t: ^Tetromino) {
  if t.type == .O do return
  for &p in t.minos {
    p.x, p.y = (t.type == .I ? 1: 0)-p.y, p.x-2
  }
}

// random generator
spawn_tetromino :: proc() -> Tetromino {
  if card(state.bag) == 0 {
    state.bag = { .I, .J, .L, .O, .S, .T, .Z }
  }

  t: TetrominoType
  ok: bool
  if !state.first_piece_drawn {
    t, ok = rand.choice_bit_set(bit_set[TetrominoType]{ .I, .J, .L, .T })
    state.first_piece_drawn = true
  } else {
    t, ok = rand.choice_bit_set(state.bag)
  }

  assert(ok)
  state.bag -= { t }
  when ODIN_DEBUG do fmt.printfln("Bag: %v", state.bag)
  tetros[t].pos.x = rand.int32_range(0, 10)
  return tetros[t]
}

init_game :: proc() {
  mino_tex = rl.LoadTexture("res/mino.png")

  state.bag = {}
  state.first_piece_drawn = false
  state.cur = spawn_tetromino()
  // for &t in state.next {
  //   t = spawn_tetromino()
  // }
}

main :: proc() {
  // todo: screen resizing while keeping all elements looking good.
  rl.InitWindow(SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX, "tetris")
  defer rl.CloseWindow()

  init_game()

  dbg_tetros := tetros

  for !rl.WindowShouldClose() {
    dt := rl.GetFrameTime()

    tick(&state.cur, dt)

    when ODIN_DEBUG {
      // for &t in dbg_tetros {
      //   tick(&t, dt)
      // }
    }

    if rl.IsKeyPressed(.SPACE) {
      state.cur = spawn_tetromino()
    }
    if rl.IsKeyPressed(.UP) {
      rotate_clockwise(&state.cur)
    } else if rl.IsKeyPressed(.Z) {
      rotate_clockwise(&state.cur)
      rotate_clockwise(&state.cur)
      rotate_clockwise(&state.cur)
    }
    if rl.IsKeyDown(.DOWN) {
      state.cur.accum_y += SOFT_SPEED*dt
    }
    if rl.IsKeyDown(.LEFT) {
      state.cur.accum_x -= SIDE_SPEED*dt
    }
    if rl.IsKeyDown(.RIGHT) {
      state.cur.accum_x += SIDE_SPEED*dt
    }

    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)

    when ODIN_DEBUG {
      for &c, i in tetroColor {
        render_mino(-8, i32(i), c)
      }
      for &t, i in dbg_tetros {
        idx := i32(i)
        t.pos = {(idx<4?10:15), i32((idx<4?idx*4:(idx-4)*4))}
        render_tetromino(&t)
      }
    }

    render_tetromino(&state.cur)
    render_game_wireframe()

    rl.EndDrawing()
  }
}
