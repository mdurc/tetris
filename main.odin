package main

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

DBG :: #config(DBG, false)

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

FALL_SPEED :: 1.0 // grid cell/second
SOFT_SPEED :: FALL_SPEED * 15

DAS_DELAY_MS :: 180.0  // initial delay before repeating (delayed-auto-shift)
ARR_DELAY_MS :: 40.0   // delay between repeated movements (auto-repeat-rate)
LOCK_DELAY_MS :: 500.0 // time a tetro waits on the ground before locking

LockDelayMode :: enum { GRAVITY, TIME_BASED, MOVE_RESET_CAPPED, MOVE_RESET_INFINITE }
LOCK_MODE :: LockDelayMode.MOVE_RESET_CAPPED
MAX_LOCK_RESETS :: 15

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

// https://tetris.wiki/Super_Rotation_System (we invert y's because +y is down for us)
// SRS wall kick tables: [rot_state][0:CCW, 1:CW][kick_test]
KICKS_JLSTZ := [4][2][5][2]i32{
  {{{ 0, 0}, {+1, 0}, {+1,-1}, { 0,+2}, {+1,+2}},   // 0 -> L
   {{ 0, 0}, {-1, 0}, {-1,-1}, { 0,+2}, {-1,+2}},}, // 0 -> R
  {{{ 0, 0}, {+1, 0}, {+1,+1}, { 0,-2}, {+1,-2}},   // 1 -> L
   {{ 0, 0}, {+1, 0}, {+1,+1}, { 0,-2}, {+1,-2}},}, // 1 -> R
  {{{ 0, 0}, {-1, 0}, {-1,-1}, { 0,+2}, {-1,+2}},   // 2 -> L
   {{ 0, 0}, {+1, 0}, {+1,-1}, { 0,+2}, {+1,+2}},}, // 2 -> R
  {{{ 0, 0}, {-1, 0}, {-1,+1}, { 0,-2}, {-1,-2}},   // 3 -> L
   {{ 0, 0}, {-1, 0}, {-1,+1}, { 0,-2}, {-1,-2}},}, // 3 -> R
}
KICKS_I := [4][2][5][2]i32{
  {{{ 0, 0}, {-1, 0}, {+2, 0}, {-1,-2}, {+2,+1}},   // 0 -> L
   {{ 0, 0}, {-2, 0}, {+1, 0}, {-2,+1}, {+1,-2}},}, // 0 -> R
  {{{ 0, 0}, {+2, 0}, {-1, 0}, {+2,-1}, {-1,+2}},   // 1 -> L
   {{ 0, 0}, {-1, 0}, {+2, 0}, {-1,-2}, {+2,+1}},}, // 1 -> R
  {{{ 0, 0}, {+1, 0}, {-2, 0}, {+1,+2}, {-2,-1}},   // 2 -> L
   {{ 0, 0}, {+2, 0}, {-1, 0}, {+2,-1}, {-1,+2}},}, // 2 -> R
  {{{ 0, 0}, {-2, 0}, {+1, 0}, {-2,+1}, {+1,-2}},   // 3 -> L
   {{ 0, 0}, {+1, 0}, {-2, 0}, {+1,+2}, {-2,-1}},}, // 3 -> R
}

Tetromino :: struct {
  type : TetrominoType,
  box_sz : i32,
  minos : [4][2]i32, // offsets from pos
  pos : [2]i32,
  rot_state : i32, // [0..3]
  accum_y: f32,
  lock_timer_ms : f32, lock_resets : i32,
}
tetros : [TetrominoType]Tetromino = {
  .I = { type = .I, box_sz = 4, minos = {{0,1},{1,1},{2,1},{3,1}} },
  .J = { type = .J, box_sz = 3, minos = {{0,0},{0,1},{1,1},{2,1}} },
  .L = { type = .L, box_sz = 3, minos = {{0,1},{1,1},{2,1},{2,0}} },
  .O = { type = .O, box_sz = 2, minos = {{0,1},{0,0},{1,0},{1,1}} },
  .S = { type = .S, box_sz = 3, minos = {{0,1},{1,1},{1,0},{2,0}} },
  .T = { type = .T, box_sz = 3, minos = {{0,1},{1,1},{1,0},{2,1}} },
  .Z = { type = .Z, box_sz = 3, minos = {{0,0},{1,0},{1,1},{2,1}} },
}

State :: struct {
  cur, hold : Tetromino,
  has_held : bool,

  next : [3]Tetromino,

  // tetro generator
  bag : bit_set[TetrominoType],
  first_piece_drawn : bool,

  grid : [GAME_HEIGHT_UNITS][GAME_WIDTH_UNITS]struct { filled: bool, type: TetrominoType } ,

  lines, level, score : i32,

  das_timer_ms, arr_timer_ms : f32,
  active_dir : i32, // -1 for left, 1 for right, 0 for none
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

render_mino :: proc(grid_x, grid_y: i32, type: TetrominoType) {
  rl.DrawTexture(mino_tex, sx+grid_x*dm, sy+grid_y*dm, tetroColor[type])
}

render_tetro :: proc(t: ^Tetromino) {
  for &p in t.minos {
    render_mino(t.pos.x+p.x, t.pos.y+p.y, t.type)
  }
  when DBG {
    rl.DrawRectangleLinesEx({f32(sx+t.pos.x*dm), f32(sy+t.pos.y*dm), f32(t.box_sz*dm), f32(t.box_sz*dm)}, 3, rl.DARKPURPLE)
  }
}

render_grid :: proc() {
  x, y : i32
  for x = 0; x < GAME_WIDTH_UNITS; x += 1 {
    for y = 0; y < GAME_HEIGHT_UNITS; y += 1 {
      if state.grid[y][x].filled {
        render_mino(x, y, state.grid[y][x].type)
      }
    }
  }
}

is_valid_placement :: proc(grid_x, grid_y: i32, minos: [][2]i32) -> bool {
  for p in minos {
    x, y := grid_x+p.x, grid_y+p.y
    if x < 0 || x >= GAME_WIDTH_UNITS || y >= GAME_HEIGHT_UNITS || (y >= 0 && state.grid[y][x].filled) {
      return false
    }
  }
  return true
}

is_grounded :: proc(t: ^Tetromino) -> bool { return !is_valid_placement(t.pos.x, t.pos.y+1, t.minos[:]) }

trigger_lock_reset :: proc() {
  if LOCK_MODE == .GRAVITY || LOCK_MODE == .TIME_BASED {
    return
  }
  if is_grounded(&state.cur) {
    if LOCK_MODE == .MOVE_RESET_INFINITE {
      state.cur.lock_timer_ms = 0.0
    } else if LOCK_MODE == .MOVE_RESET_CAPPED {
      fmt.printfln("reset: %v/%v", state.cur.lock_resets, MAX_LOCK_RESETS)
      if state.cur.lock_resets < MAX_LOCK_RESETS {
        state.cur.lock_timer_ms = 0.0
        state.cur.lock_resets += 1
      }
    }
  }
}

tick :: proc(t: ^Tetromino, dt_s, dt_ms: f32) {
  if is_grounded(t) {
    t.accum_y = 0.0 // turn off gravity, rely on lock delay
    state.cur.lock_timer_ms += dt_ms
    // fmt.println(state.cur.lock_timer_ms, "/", LOCK_DELAY_MS)
    if state.cur.lock_timer_ms >= LOCK_DELAY_MS {
      lock_tetro(t)
      state.cur = spawn_tetro()
    }
    return
  }

  state.cur.lock_timer_ms = 0.0
  t.accum_y += FALL_SPEED * dt_s
  dy := i32(t.accum_y)
  if dy > 0 {
    t.accum_y -= f32(dy)
    // move down one space at a time
    for i : i32 = 0; i < dy; i += 1 {
      if !try_move(t, 0, 1) {
        // next frame will handle lock delay
        break
      }
    }
  }
}

try_rotate :: proc(t: ^Tetromino, clockwise: bool) -> bool {
  if t.type == .O do return false

  next_minos := t.minos
  for &p in next_minos {
    if clockwise {
      p.x, p.y = (t.type == .I ? 3: 2)-p.y, p.x
    } else {
      p.x, p.y = p.y, (t.type == .I ? 3: 2)-p.x
    }
  }

  next_state := (t.rot_state + (clockwise ? 1 : 3)) % 4
  dir_idx := clockwise ? 1 : 0
  kicks := t.type == .I ? KICKS_I[t.rot_state][dir_idx][:] : KICKS_JLSTZ[t.rot_state][dir_idx][:]
  for k in kicks {
    if is_valid_placement(t.pos.x+k.x, t.pos.y+k.y, next_minos[:]) {
      t.minos = next_minos
      t.pos += k
      t.rot_state = next_state
      trigger_lock_reset()
      return true
    }
  }
  return false
}

try_move :: proc(t: ^Tetromino, dx, dy: i32) -> bool {
  if is_valid_placement(t.pos.x+dx, t.pos.y+dy, t.minos[:]) {
    t.pos.x += dx
    t.pos.y += dy

    if dx != 0 {
      // any horizontal movement will trigger reset
      trigger_lock_reset()
    }
    return true
  }
  return false
}

// random generator
spawn_tetro :: proc() -> Tetromino {
  if card(state.bag) == 0 {
    state.bag = { .I, .J, .L, .O, .S, .T, .Z }
  }

  t_type: TetrominoType
  ok: bool
  if !state.first_piece_drawn {
    t_type, ok = rand.choice_bit_set(bit_set[TetrominoType]{ .I, .J, .L, .T })
    state.first_piece_drawn = true
  } else {
    t_type, ok = rand.choice_bit_set(state.bag)
  }

  assert(ok)
  state.bag -= { t_type }
  when DBG do fmt.printfln("Bag: %v", state.bag)
  t := tetros[t_type]
  // t.pos.x = rand.int32_range(0, GAME_WIDTH_UNITS-tetros[t_type].box_sz+1)
  t.pos.x = (t_type == .O) ? 4 : 3 // start in the center
  t.pos.y = -2
  return t
}

lock_tetro :: proc(t: ^Tetromino) {
  for &p in t.minos {
    x, y := t.pos.x+p.x, t.pos.y+p.y
    if x >= 0 && x < GAME_WIDTH_UNITS && y >= 0 && y < GAME_HEIGHT_UNITS {
      state.grid[y][x] = { true, t.type }
    }
  }

  x, y, lines_cleared : i32
  last_cleared_y : i32 = GAME_HEIGHT_UNITS - 1
  for y = GAME_HEIGHT_UNITS-1; y >= 0; y -= 1 {
    is_filled := true
    for x = 0; x < GAME_WIDTH_UNITS; x += 1 {
      if !state.grid[y][x].filled {
        is_filled = false
        break
      }
    }
    if is_filled {
      lines_cleared += 1
    } else {
      state.grid[last_cleared_y] = state.grid[y]
      last_cleared_y -= 1
    }
  }
  for y = last_cleared_y; y >= 0; y -= 1 {
    state.grid[y] = {}
  }
  state.lines += lines_cleared
}

init_game :: proc() {
  mino_tex = rl.LoadTexture("res/mino.png")

  state.bag = {}
  state.first_piece_drawn = false
  state.cur = spawn_tetro()
  // for &t in state.next {
  //   t = spawn_tetro()
  // }
}

main :: proc() {
  // todo: screen resizing while keeping all elements looking good.
  rl.InitWindow(SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX, "tetris")
  defer rl.CloseWindow()

  init_game()
  defer rl.UnloadTexture(mino_tex)

  dbg_tetros := tetros
  for !rl.WindowShouldClose() {
    dt_s := rl.GetFrameTime()
    dt_ms := dt_s * 1000.0

    if rl.IsKeyPressed(.SPACE) {
      for is_valid_placement(state.cur.pos.x, state.cur.pos.y+1, state.cur.minos[:]) {
        state.cur.pos.y += 1
      }
      lock_tetro(&state.cur)
      state.cur = spawn_tetro()
    }

    if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.X) {
      try_rotate(&state.cur, true)
    } else if rl.IsKeyPressed(.Z) {
      try_rotate(&state.cur, false)
    }

    if rl.IsKeyDown(.DOWN) {
      state.cur.accum_y += SOFT_SPEED*dt_s
    }

    first_left, first_right := rl.IsKeyPressed(.LEFT), rl.IsKeyPressed(.RIGHT)
    left_down, right_down := rl.IsKeyDown(.LEFT), rl.IsKeyDown(.RIGHT)
    if first_left {
      state.active_dir = -1
      state.das_timer_ms, state.arr_timer_ms = 0.0, 0.0
      try_move(&state.cur, -1, 0)
    } else if first_right {
      state.active_dir = 1
      state.das_timer_ms, state.arr_timer_ms = 0.0, 0.0
      try_move(&state.cur, 1, 0)
    }

    is_active_key_held := (state.active_dir == -1 && left_down) || (state.active_dir == 1 && right_down)
    if is_active_key_held {
      state.das_timer_ms += dt_ms
      if state.das_timer_ms >= DAS_DELAY_MS {
        state.arr_timer_ms += dt_ms
        for state.arr_timer_ms >= ARR_DELAY_MS {
          try_move(&state.cur, state.active_dir, 0)
          state.arr_timer_ms -= ARR_DELAY_MS
        }
      }
    } else {
      state.active_dir = 0
      // check if the inactive direction is being held
      if left_down {
        state.active_dir = -1
        state.das_timer_ms = DAS_DELAY_MS
      } else if right_down {
        state.active_dir = 1
        state.das_timer_ms = DAS_DELAY_MS
      }
    }

    tick(&state.cur, dt_s, dt_ms)

    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)

    when DBG {
      for &c, i in tetroColor {
        render_mino(-8, i32(i), i)
      }
      for &t, i in dbg_tetros {
        idx := i32(i)
        t.pos = {(idx<4?10:15), i32((idx<4?idx*4:(idx-4)*4))}
        render_tetro(&t)
      }
    }

    render_grid()
    render_tetro(&state.cur)
    render_game_wireframe()

    rl.EndDrawing()
  }
}
