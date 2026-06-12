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

SPEED :: 1.0

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
  minos : [4][2]i32,
  pos : [2]i32,
  accumulator : f32
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
  when ODIN_DEBUG {
    sz_x : f32 = t.type == .I || t.type == .O ? 4*dm: 3*dm
    sz_y : f32 = t.type == .O ? 3*dm : sz_x
    rl.DrawRectangleLinesEx({f32(sx+t.pos.x*dm), f32(sy+(t.pos.y-2)*dm), sz_x, sz_y}, 3, rl.DARKPURPLE)
  }
  for &p in t.minos {
    render_mino(t.pos.x+p.x, t.pos.y+p.y, tetroColor[t.type])
  }
}

tick :: proc(t: ^Tetromino, dt: f32) {
  t.accumulator += SPEED*dt
  // fmt.println(t.accumulator)
  dy := i32(t.accumulator)
  t.accumulator -= f32(dy)
  if (dy > 0) {
    t.pos.y += dy
    rotate_clockwise(t)
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
  fmt.printfln("Bag: %v", state.bag)
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

  for !rl.WindowShouldClose() {
    dt := rl.GetFrameTime()

    tick(&state.cur, dt)

    if rl.IsKeyPressed(.SPACE) {
      state.cur = spawn_tetromino()
    }

    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)

    render_tetromino(&state.cur)
    render_game_wireframe()

    rl.EndDrawing()
  }
}
