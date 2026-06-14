package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "core:encoding/json"

DBG :: #config(DBG, false)

// -- windowing & rendering --
WINDOW_WIDTH_PX, WINDOW_HEIGHT_PX :: 1280, 960
BG_COLOR :: rl.Color{0x28, 0x29, 0x23, 0xFF}

GRID_UNIT_SIZE_PX :: 8 // pixels
GRID_WIDTH_UNITS :: 10 // # of grid cells
GRID_HEIGHT_UNITS :: GRID_WIDTH_UNITS * 2
GRID_WIDTH_PX :: GRID_UNIT_SIZE_PX*GRID_WIDTH_UNITS
GRID_HEIGHT_PX :: GRID_UNIT_SIZE_PX*GRID_HEIGHT_UNITS

RENDER_WIDTH_PX :: GRID_WIDTH_PX + (20 * GRID_UNIT_SIZE_PX)
RENDER_HEIGHT_PX :: GRID_HEIGHT_PX + (10 * GRID_UNIT_SIZE_PX)

// starting pixels that center the grid in the render view with extra space on top
GRID_START_X_PX :: (RENDER_WIDTH_PX - GRID_WIDTH_PX) / 2
GAME_START_Y_PX :: ((RENDER_HEIGHT_PX - GRID_HEIGHT_PX) / 2) + GRID_UNIT_SIZE_PX

// shorter renames
g_width, g_height :: GRID_WIDTH_PX, GRID_HEIGHT_PX
unit_sz, sx, sy :: GRID_UNIT_SIZE_PX, GRID_START_X_PX, GAME_START_Y_PX

// -- movement --
FALL_SPEED :: 1.0 // grid cell/second
SOFT_SPEED :: FALL_SPEED * 15

LOCK_DELAY_MS :: 500.0 // time a tetro waits on the ground before locking
MAX_LOCK_RESETS :: 15

// -- scoring --
SCORE_SINGLE :: 100
SCORE_DOUBLE :: 300
SCORE_TRIPLE :: 500
SCORE_TETRIS :: 800
SCORE_SOFT_DROP :: 1
SCORE_HARD_DROP :: 2
LINES_PER_LEVEL :: 10
SPEED_INCREASE_PER_LEVEL :: 0.5 // grid cells per second added per level
HIGH_SCORE_FILE :: "highscore.txt"
CONFIG_FILE :: "config.json"

// -- config --
ProgramMode :: enum { PLAYING, MENU }
MenuOption :: enum { GHOST, SFX, SHOW_UI, SHOW_NEXT, NUM_NEXT_PREVIEW, DAS_MS, ARR_MS, LOCK_MODE, MOUSE_CTRL, RESET_CFG, SAVE_CFG, RESTART, RESET_HS }
LockDelayMode :: enum { GRAVITY, TIME_BASED, RESET_CAPPED, RESET_INFINITE }
Config :: struct {
  show_ghost, sfx_enabled, mouse_enabled, show_all_ui, show_next: bool,
  num_next: int,
  das_ms: f32,
  arr_ms: f32,
  lock_mode: LockDelayMode,
}

OPTION_MENU_ICON :: rl.Rectangle{ sx+g_width+unit_sz*4, sy-unit_sz*4, unit_sz, unit_sz }

DEFAULT_CONFIG :: Config {
  show_ghost = true, sfx_enabled = true,
  mouse_enabled = true, show_all_ui = true, show_next = true,
  num_next = 3,
  das_ms = 180.0, // initial delay before repeating (delayed-auto-shift)
  arr_ms = 40.0,  // delay between repeated movements (auto-repeat-rate)
  lock_mode = .RESET_CAPPED,
}

// -- styling --
ColorScheme :: enum { SAPHIRE, RUBY, EMERALD, AMETHYST, CHERRY, TOOTHPASTE, ASH, WINE, BUBBLEGUM, CHARCOAL }
FrameStyle :: struct { edge, corner: [2]int }

FRAME_GAME :: FrameStyle{ edge = {2, 5}, corner = {1, 5} }
FRAME_INFO :: FrameStyle{ edge = {4, 5}, corner = {3, 5} }

PanelID :: enum { HOLD, BOARD, NEXT, STATS, LINES, MENU }
Panel :: struct { bounds: rl.Rectangle, style: FrameStyle }

ASCII_MAX :: 256

// https://tetris.wiki/Super_Rotation_System (we invert y's because +y is down for us)
// SRS wall kick tables: [rot_state][0:CCW, 1:CW][kick_test]
@(rodata)
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
@(rodata)
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

TetrominoType :: enum { I, J, L, O, S, T, Z }
Tetromino :: struct {
  type : TetrominoType,
  box_sz : i32,
  minos : [4][2]i32, // offsets from pos
  pos : [2]i32,
  rot_state : i32, // [0..3]
  accum_y: f32,
  lock_timer_ms : f32, lock_resets : i32,
}

@(rodata)
TETROS : [TetrominoType]Tetromino = {
  .I = { type = .I, box_sz = 4, minos = {{0,1},{1,1},{2,1},{3,1}} },
  .J = { type = .J, box_sz = 3, minos = {{0,0},{0,1},{1,1},{2,1}} },
  .L = { type = .L, box_sz = 3, minos = {{0,1},{1,1},{2,1},{2,0}} },
  .O = { type = .O, box_sz = 2, minos = {{0,1},{0,0},{1,0},{1,1}} },
  .S = { type = .S, box_sz = 3, minos = {{0,1},{1,1},{1,0},{2,0}} },
  .T = { type = .T, box_sz = 3, minos = {{0,1},{1,1},{1,0},{2,1}} },
  .Z = { type = .Z, box_sz = 3, minos = {{0,0},{1,0},{1,1},{2,1}} },
}

State :: struct {
  mode: ProgramMode,
  config: Config,
  menu_idx: int,

  cur, hold : Tetromino,
  hold_locked, is_holding_tetro : bool,
  next : [3]Tetromino,
  grid : [GRID_HEIGHT_UNITS][GRID_WIDTH_UNITS]struct { filled: bool, type: TetrominoType },
  lines, level, high_score, score : i32,

  // tetro generator
  bag : bit_set[TetrominoType],
  first_piece_drawn : bool,

  // movement
  das_timer_ms, arr_timer_ms : f32,
  active_dir : i32, // -1 for left, 1 for right, 0 for none

  theme: ColorScheme,
  zoom: f32,
}

// -- mutable globals --
state : State
atlas_tex : rl.Texture2D
font_map: [ASCII_MAX][2]int
ui_panels: [PanelID]Panel

load_high_score :: proc() {
  data, err := os.read_entire_file(HIGH_SCORE_FILE, context.allocator)
  if err != nil {
    fmt.printfln("ERROR: failed to read file %s.", HIGH_SCORE_FILE)
    return
  }
  defer delete(data, context.allocator)
  if val, ok := strconv.parse_int(string(data)); ok {
    state.high_score = i32(val)
  }
  fmt.printfln("Parsed highscore %d from %s.", state.high_score, HIGH_SCORE_FILE)
}

save_high_score :: proc() {
  buf: [32]byte
  str := fmt.bprintf(buf[:], "%d", state.high_score)
  err := os.write_entire_file(HIGH_SCORE_FILE, str)
  if err != nil {
    fmt.printfln("ERROR: failed to write file %s.", HIGH_SCORE_FILE)
    return
  }
  fmt.printfln("Saved highscore %d to file: %s.", state.high_score, HIGH_SCORE_FILE)
}

load_config :: proc() {
  data, err := os.read_entire_file(CONFIG_FILE, context.allocator)
  if err != nil {
    fmt.printfln("ERROR: failed to read file %s.", CONFIG_FILE)
    return
  }
  defer delete(data, context.allocator)
  json.unmarshal(data, &state.config)
}

save_config :: proc() {
  data, err_m := json.marshal(state.config, {pretty = true})
  if err_m != nil {
    fmt.println("ERROR: failed to marshal config.")
    return
  }
  defer delete(data)

  err := os.write_entire_file(CONFIG_FILE, data)
  if err != nil {
    fmt.printfln("ERROR: failed to write file %s.", CONFIG_FILE)
    return
  }
  fmt.printfln("Saved config to file: %s.", CONFIG_FILE)
}

reset_state :: proc(first_time_init: bool) {
  old := state
  state = {}
  state.mode = .PLAYING
  state.config = first_time_init ? DEFAULT_CONFIG: old.config
  state.zoom = first_time_init ? 1.0: old.zoom
  state.theme = first_time_init ? .CHERRY: old.theme
  state.high_score = old.high_score
  if first_time_init {
    // attempt loads
    load_config()
    load_high_score()
  }
  for &t in state.next {
    t = spawn_tetro()
  }
  state.cur = pop_next()
}

init_game :: proc() {
  init_ui :: proc() {
    font_lines := [5]string{"ABCDEFGHIJKLMNOP", "QRSTUVWXYZ_ ", "abcdefghijklmnop", "qrstuvwxyz/\\[]=%", "0123456789.!?-:>"}
    for &i in font_map {
      i = {-1, -1}
    }
    for y in 0..<len(font_lines) {
      for c, x in font_lines[y] {
        if int(c) < ASCII_MAX {
          font_map[int(c)] = {x, y};
        }
      }
    }

    // setup absolute bounds for each panel
    menu_w, menu_h : f32 = 25*unit_sz, len(MenuOption)*12+unit_sz*4
    ui_panels = {
      .LINES = { rl.Rectangle{sx, sy - 4*unit_sz, g_width, unit_sz}, FRAME_INFO },
      .BOARD = { rl.Rectangle{sx, sy, g_width, g_height}, FRAME_GAME },
      .HOLD  = { rl.Rectangle{sx - 7*unit_sz, sy, 4*unit_sz, 4*unit_sz}, FRAME_GAME },
      .STATS = { rl.Rectangle{sx - 9*unit_sz, sy+g_height-9*unit_sz, 6*unit_sz, 9*unit_sz}, FRAME_INFO },
      .NEXT  = { rl.Rectangle{sx + g_width + 3*unit_sz, sy, 4*unit_sz, 11*unit_sz}, FRAME_GAME },
      .MENU  = { rl.Rectangle{f32((RENDER_WIDTH_PX-menu_w)/2), f32((RENDER_HEIGHT_PX-menu_h)/2), menu_w, menu_h}, FRAME_GAME },
    }
  }

  init_ui()
  atlas_tex = rl.LoadTexture("res/atlas.png")
  rl.SetTextureFilter(atlas_tex, .POINT)

  reset_state(true)
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
  t := TETROS[t_type]
  // t.pos.x = rand.int32_range(0, GRID_WIDTH_UNITS-TETROS[t_type].box_sz+1)
  t.pos.x = (t_type == .O) ? 4 : 3 // start in the center
  t.pos.y = -2
  return t
}

pop_next :: proc() -> Tetromino {
  popped := state.next[0]
  state.next[0] = state.next[1]
  state.next[1] = state.next[2]
  state.next[2] = spawn_tetro()
  return popped
}

is_valid_placement :: proc(grid_x, grid_y: i32, minos: [][2]i32) -> bool {
  for p in minos {
    x, y := grid_x+p.x, grid_y+p.y
    if x < 0 || x >= GRID_WIDTH_UNITS || y >= GRID_HEIGHT_UNITS || (y >= 0 && state.grid[y][x].filled) {
      return false
    }
  }
  return true
}

is_grounded :: proc() -> bool { return !is_valid_placement(state.cur.pos.x, state.cur.pos.y+1, state.cur.minos[:]) }

try_move :: proc(dx, dy: i32) -> bool {
  cur := &state.cur
  if is_valid_placement(cur.pos.x+dx, cur.pos.y+dy, cur.minos[:]) {
    cur.pos.x += dx
    cur.pos.y += dy
    if dx != 0  {
      // horizontal movement triggers reset
      trigger_lock_reset()
    }
    return true
  }
  return false
}

try_rotate :: proc(clockwise: bool) -> bool {
  cur := &state.cur
  if cur.type == .O {
    return false
  }

  next_minos := cur.minos
  for &p in next_minos {
    if clockwise {
      p.x, p.y = (cur.type == .I ? 3: 2)-p.y, p.x
    } else {
      p.x, p.y = p.y, (cur.type == .I ? 3: 2)-p.x
    }
  }

  next_state := (cur.rot_state + (clockwise ? 1 : 3)) % 4
  dir_idx := clockwise ? 1 : 0
  kicks := cur.type == .I ? KICKS_I[cur.rot_state][dir_idx][:] : KICKS_JLSTZ[cur.rot_state][dir_idx][:]
  for k in kicks {
    if is_valid_placement(cur.pos.x+k.x, cur.pos.y+k.y, next_minos[:]) {
      cur.minos = next_minos
      cur.pos += k
      cur.rot_state = next_state
      trigger_lock_reset()
      return true
    }
  }
  return false
}

trigger_lock_reset :: proc() {
  if state.config.lock_mode == .GRAVITY || state.config.lock_mode == .TIME_BASED {
    return
  }
  if is_grounded() {
    if state.config.lock_mode == .RESET_INFINITE {
      state.cur.lock_timer_ms = 0.0
    } else if state.config.lock_mode == .RESET_CAPPED {
      fmt.printfln("reset: %v/%v", state.cur.lock_resets, MAX_LOCK_RESETS)
      if state.cur.lock_resets < MAX_LOCK_RESETS {
        state.cur.lock_timer_ms = 0.0
        state.cur.lock_resets += 1
      }
    }
  }
}

lock_tetro :: proc() {
  state.hold_locked = false // reset hold lock
  cur := &state.cur

  for &p in cur.minos {
    x, y := cur.pos.x+p.x, cur.pos.y+p.y
    if x >= 0 && x < GRID_WIDTH_UNITS && y >= 0 && y < GRID_HEIGHT_UNITS {
      state.grid[y][x] = { true, cur.type }
    }
  }

  x, y, lines_cleared : i32
  last_cleared_y : i32 = GRID_HEIGHT_UNITS - 1
  for y = GRID_HEIGHT_UNITS-1; y >= 0; y -= 1 {
    is_filled := true
    for x = 0; x < GRID_WIDTH_UNITS; x += 1 {
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

  if lines_cleared > 0 {
    state.lines += lines_cleared
    state.level = state.lines / LINES_PER_LEVEL
    multiplier := state.level + 1 // level 0 is multiplier 1
    switch lines_cleared {
    case 1: state.score += SCORE_SINGLE*multiplier
    case 2: state.score += SCORE_DOUBLE*multiplier
    case 3: state.score += SCORE_TRIPLE*multiplier
    case 4: state.score += SCORE_TETRIS*multiplier
    }
  }

  if state.score > state.high_score {
    state.high_score = state.score
    save_high_score()
  }
}

tick :: proc(dt_s, dt_ms: f32, is_soft_dropping: bool) {
  cur := &state.cur
  if is_grounded() {
    cur.accum_y = 0.0 // turn off gravity, rely on lock delay
    state.cur.lock_timer_ms += dt_ms
    // fmcur.println(state.cur.lock_timer_ms, "/", LOCK_DELAY_MS)
    if state.cur.lock_timer_ms >= LOCK_DELAY_MS {
      lock_tetro()
      state.cur = pop_next()
    }
    return
  }

  state.cur.lock_timer_ms = 0.0

  // dynamic gravity based on level
  base_fall_speed := FALL_SPEED + (f32(state.level) * SPEED_INCREASE_PER_LEVEL)
  current_speed := is_soft_dropping ? (base_fall_speed * SOFT_SPEED) : base_fall_speed

  cur.accum_y += current_speed * dt_s
  dy := i32(cur.accum_y)

  if dy > 0 {
    cur.accum_y -= f32(dy)
    // move down one space at a time
    for i : i32 = 0; i < dy; i += 1 {
      if try_move(0, 1) {
        if is_soft_dropping {
          state.score += SCORE_SOFT_DROP
        }
      } else {
        // next frame will handle lock delay
        break
      }
    }
  }
}

// -- rendering --
atlas_render_sprite :: proc(src_x, src_y: int, dst: rl.Vector2, c: rl.Color = rl.WHITE) {
  src_rec := rl.Rectangle { f32(src_x*unit_sz), f32(src_y*unit_sz), unit_sz, unit_sz }
  rl.DrawTextureRec(atlas_tex, src_rec, dst, c)
}

render_mino_absolute :: proc(px, py: f32, type: TetrominoType) {
  src_x := 0
  src_y := 6 + int(state.theme) // ATLAS_MINOS_OFFSET_Y_UNITS :: 6
  switch type {
  case .L, .S: src_x = 0
  case .Z, .J: src_x = 1
  case .T, .O, .I: src_x = 2
  }
  atlas_render_sprite(src_x, src_y, {px, py})
}

render_playfield :: proc() {
  for x in 0..<GRID_WIDTH_UNITS {
    for y in 0..<GRID_HEIGHT_UNITS {
      if state.grid[y][x].filled {
        render_mino_absolute(f32(sx+x*unit_sz), f32(sy+y*unit_sz), state.grid[y][x].type)
      }
    }
  }
}

render_ghost :: proc(t: ^Tetromino) {
  ghost_y := t.pos.y
  for is_valid_placement(t.pos.x, ghost_y + 1, t.minos[:]) {
    ghost_y += 1
  }
  for &p in t.minos {
    atlas_render_sprite(0, 5, {f32(sx+(t.pos.x+p.x)*unit_sz), f32(sy+(ghost_y+p.y)*unit_sz)})
  }
}

render_tetro :: proc(t: ^Tetromino) {
  for &p in t.minos {
    render_mino_absolute(f32(sx+(t.pos.x+p.x)*unit_sz), f32(sy+(t.pos.y+p.y)*unit_sz), t.type)
  }
}

render_str :: proc(s: string, x, y: f32, c: rl.Color = rl.WHITE) {
  find_char :: proc(c: rune) -> (src_x, src_y: int) {
    idx := c < ASCII_MAX ? c : '?'
    cx, cy := font_map[idx].x, font_map[idx].y
    if cx == -1 || cy == -1 {
      return find_char('?')
    }
    return cx, cy
  }

  dst_x, dst_y := x, y
  for ch in s {
    if ch == '\n' {
      dst_y += 9
      dst_x = x
    } else {
      src_x, src_y := find_char(ch)
      atlas_render_sprite(src_x, src_y, {dst_x, dst_y}, c)
      dst_x += 8
    }
  }
}

render_panel :: proc(p: ^Panel) {
  bx, by, bw, bh := p.bounds.x, p.bounds.y, p.bounds.width, p.bounds.height

  rl.DrawRectangleV({bx - unit_sz, by - unit_sz}, {bw + unit_sz*2, bh + unit_sz*2}, rl.BLACK)

  ex, ey := f32(p.style.edge.x)*unit_sz, f32(p.style.edge.y)*unit_sz
  cx, cy := f32(p.style.corner.x)*unit_sz, f32(p.style.corner.y)*unit_sz

  // draw edges (stretch)
  rl.DrawTexturePro(atlas_tex, {ex, ey, unit_sz, unit_sz}, {bx, by - unit_sz, bw, unit_sz}, {0,0}, 0.0, rl.WHITE)
  rl.DrawTexturePro(atlas_tex, {ex, ey, unit_sz, -unit_sz}, {bx, by + bh, bw, unit_sz}, {0,0}, 0.0, rl.WHITE)
  rl.DrawTexturePro(atlas_tex, {ex, ey, unit_sz, unit_sz}, {bx - unit_sz, by + bh, bh, unit_sz}, {0,0}, -90.0, rl.WHITE)
  rl.DrawTexturePro(atlas_tex, {ex, ey, unit_sz, -unit_sz}, {bx + bw, by + bh, bh, unit_sz}, {0,0}, -90.0, rl.WHITE)

  // draw corners
  rl.DrawTextureRec(atlas_tex, {cx, cy, unit_sz, unit_sz}, {bx - unit_sz, by - unit_sz}, rl.WHITE)
  rl.DrawTextureRec(atlas_tex, {cx, cy, -unit_sz, unit_sz}, {bx + bw, by - unit_sz}, rl.WHITE)
  rl.DrawTextureRec(atlas_tex, {cx, cy, unit_sz, -unit_sz}, {bx - unit_sz, by + bh}, rl.WHITE)
  rl.DrawTextureRec(atlas_tex, {cx, cy, -unit_sz, -unit_sz}, {bx + bw, by + bh}, rl.WHITE)
}

render_ui :: proc() {
  render_tetro_centered :: proc(panel_id: PanelID, t: ^Tetromino, y_offset_units: f32) {
    panel := ui_panels[panel_id]
    center_x := panel.bounds.x + (panel.bounds.width / 2.0)
    center_y := panel.bounds.y + (y_offset_units * unit_sz)
    cx_offset := f32(t.box_sz) * unit_sz / 2.0
    for p in t.minos {
      render_mino_absolute(center_x-cx_offset + (f32(p.x)*unit_sz), center_y + (f32(p.y)*unit_sz), t.type)
    }
  }

  render_panel(&ui_panels[.BOARD])
  render_str("X", OPTION_MENU_ICON.x, OPTION_MENU_ICON.y)

  if state.config.show_all_ui {
    render_panel(&ui_panels[.LINES])
    render_panel(&ui_panels[.HOLD])
    render_panel(&ui_panels[.STATS])

    buf: [64]byte
    stats_str := fmt.bprintf(buf[:], "TOP\n%06d\n\nSCORE\n%06d\n\nLEVEL\n%06d", state.high_score, state.score, state.level)
    render_str(stats_str, ui_panels[.STATS].bounds.x, ui_panels[.STATS].bounds.y)
    render_str("HOLD", ui_panels[.HOLD].bounds.x, ui_panels[.HOLD].bounds.y)

    lines_str := fmt.bprintf(buf[:], "LINES-%0*d", (GRID_WIDTH_UNITS >= 10 ? 4: GRID_WIDTH_UNITS == 9 ? 3: 2), state.lines)
    render_str(lines_str, ui_panels[.LINES].bounds.x, ui_panels[.LINES].bounds.y)

    if state.is_holding_tetro {
      render_tetro_centered(.HOLD, &state.hold, 1.5)
    }

    if state.config.show_next {
      render_panel(&ui_panels[.NEXT])
      render_str("NEXT", ui_panels[.NEXT].bounds.x, ui_panels[.NEXT].bounds.y)
      for &t, i in state.next {
        if i >= state.config.num_next {
          break
        }
        render_tetro_centered(.NEXT, &t, f32(i*3+2))
      }
    }
  }
}

render_menu :: proc() {
  rl.DrawRectangle(0, 0, i32(RENDER_WIDTH_PX), i32(RENDER_HEIGHT_PX), {0, 0, 0, 210})
  render_panel(&ui_panels[.MENU])

  menu_text_x := ui_panels[.MENU].bounds.x+16.0
  menu_text_y := ui_panels[.MENU].bounds.y+12.0

  buf: [128]byte
  hover_buf: [128]byte
  for o, i in MenuOption {
    str: string
    switch MenuOption(i) {
    case .GHOST: str = fmt.bprintf(buf[:], "GHOST: %s", state.config.show_ghost ? "ON":"OFF")
    case .SFX: str = fmt.bprintf(buf[:], "SFX: %s", state.config.sfx_enabled ? "ON":"OFF")
    case .SHOW_UI: str = fmt.bprintf(buf[:], "SHOW UI: %s", state.config.show_all_ui ? "ON":"OFF")
    case .SHOW_NEXT: str = fmt.bprintf(buf[:], "SHOW NEXT: %s", state.config.show_next ? "ON":"OFF")
    case .NUM_NEXT_PREVIEW: str = fmt.bprintf(buf[:], "NEXT PREVIEWS: %d", state.config.num_next)
    case .DAS_MS: str = fmt.bprintf(buf[:], "DAS MS: %.0f", state.config.das_ms)
    case .ARR_MS: str = fmt.bprintf(buf[:], "ARR MS: %.0f", state.config.arr_ms)
    case .LOCK_MODE: str = fmt.bprintf(buf[:], "LOCK: %s", state.config.lock_mode)
    case .MOUSE_CTRL: str = fmt.bprintf(buf[:], "MOUSE: %s", state.config.mouse_enabled ? "ON":"OFF")
    case .RESET_CFG: str = "RESET CONFIG"
    case .SAVE_CFG: str = "SAVE CONFIG"
    case .RESTART: str = "RESTART GAME"
    case .RESET_HS: str = "RESET HIGHSCORE"
    }
    color := (i == state.menu_idx) ? rl.YELLOW : rl.WHITE
    if i == state.menu_idx {
      str = fmt.bprintf(hover_buf[:], "> %s", str)
    }
    render_str(str, menu_text_x, menu_text_y + f32(i*8), color)
  }
  keybinds := "L/R: Move\nDOWN: Soft\nSPC/L-CLK: Hard\nC/M-CLK: Hold\nUP/X: Rot R    Z: Rot L\nESC/O: Menu    -/=: Zoom"
  render_str(keybinds, ui_panels[.MENU].bounds.x, ui_panels[.MENU].bounds.y+ui_panels[.MENU].bounds.height-unit_sz*7, rl.LIGHTGRAY)
}

main :: proc() {
  rl.SetConfigFlags({.WINDOW_RESIZABLE})
  rl.InitWindow(WINDOW_WIDTH_PX, WINDOW_HEIGHT_PX, "tetris")
  defer rl.CloseWindow()
  rl.SetExitKey(.KEY_NULL)

  init_game()
  defer rl.UnloadTexture(atlas_tex)

  // create the render canvas
  target := rl.LoadRenderTexture(RENDER_WIDTH_PX, RENDER_HEIGHT_PX)
  defer rl.UnloadRenderTexture(target)
  rl.SetTextureFilter(target.texture, .POINT)

  for !rl.WindowShouldClose() {
    dt_s := rl.GetFrameTime()
    dt_ms := dt_s * 1000.0

    screen_w, screen_h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
    target_w, target_h := f32(RENDER_WIDTH_PX), f32(RENDER_HEIGHT_PX)

    base_scale := min(screen_w/target_w, screen_h/target_h)
    scale := base_scale * state.zoom
    dst_rec_x := (screen_w - (target_w * scale)) * 0.5
    dst_rec_y := (screen_h - (target_h * scale)) * 0.5

    // input gathering (check if we want to enter the menu)
    mouse_pos := rl.GetMousePosition()
    canvas_mouse_x := (mouse_pos.x - dst_rec_x) / scale
    canvas_mouse_y := (mouse_pos.y - dst_rec_y) / scale
    mouse_click := rl.IsMouseButtonPressed(.LEFT)

    if rl.IsKeyPressed(.ESCAPE) || rl.IsKeyPressed(.O) || (mouse_click && rl.CheckCollisionPointRec({canvas_mouse_x, canvas_mouse_y}, OPTION_MENU_ICON)) {
      state.mode = state.mode == .PLAYING ? .MENU : .PLAYING
      mouse_click = false
    }

    if state.mode == .MENU {
      mouse_delta := rl.GetMouseDelta()
      if mouse_delta.x != 0 || mouse_delta.y != 0 {
        menu_text_y := ui_panels[.MENU].bounds.y + 12.0
        my := canvas_mouse_y - menu_text_y
        if my >= 0 && my < f32(len(MenuOption)*8) {
          state.menu_idx = int(my/8)
        }
      }

      // keyboard movement on menu
      if rl.IsKeyPressed(.DOWN) {
        state.menu_idx = (state.menu_idx+1) % len(MenuOption)
      }
      if rl.IsKeyPressed(.UP) {
        state.menu_idx = (state.menu_idx-1+len(MenuOption)) % len(MenuOption)
      }

      dir := -1 if rl.IsKeyPressed(.LEFT) else 1 if rl.IsKeyPressed(.RIGHT) else 0
      action := rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) || mouse_click
      if dir != 0 || action {
        switch MenuOption(state.menu_idx) {
        case .GHOST: state.config.show_ghost = !state.config.show_ghost
        case .SFX: state.config.sfx_enabled = !state.config.sfx_enabled
        case .SHOW_UI: state.config.show_all_ui = !state.config.show_all_ui
        case .SHOW_NEXT: state.config.show_next = !state.config.show_next
        case .NUM_NEXT_PREVIEW:
          state.config.num_next = ((state.config.num_next - 1 + (dir == 0 ? 1 : dir) + 3) % 3) + 1
        case .DAS_MS:
          state.config.das_ms = clamp(state.config.das_ms + f32((dir == 0 ? 1: dir) * 10), 20, 500)
        case .ARR_MS:
          state.config.arr_ms = clamp(state.config.arr_ms + f32((dir == 0 ? 1: dir) * 5), 20, 500)
        case .LOCK_MODE:
          val := int(state.config.lock_mode) + (dir == 0 ? 1: dir)
          val = (val < 0 ? 3: val > 3 ? 0: val)
          state.config.lock_mode = LockDelayMode(val)
        case .MOUSE_CTRL: state.config.mouse_enabled = !state.config.mouse_enabled
        case .RESET_CFG: if action { state.config = DEFAULT_CONFIG }
        case .SAVE_CFG: if action { save_config() }
        case .RESTART: if action { reset_state(false) }
        case .RESET_HS:
          if action {
            state.high_score = 0
            save_high_score()
          }
        }
      }
    } else {
      // input gathering
      pressed_hard_drop := rl.IsKeyPressed(.SPACE) || rl.IsMouseButtonPressed(.LEFT)
      pressed_rot_cw    := rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.X) || rl.IsMouseButtonPressed(.RIGHT)
      pressed_rot_ccw   := rl.IsKeyPressed(.Z)
      pressed_hold      := rl.IsKeyPressed(.C) || rl.IsMouseButtonPressed(.MIDDLE)
      holding_soft_drop := rl.IsKeyDown(.DOWN)

      // handle mouse input
      if state.config.mouse_enabled {
        mouse_delta := rl.GetMouseDelta()
        if mouse_delta.x != 0.0 || mouse_delta.y != 0.0 {
          // un-project window pixel to canvas pixel, then map to grid x.
          // offset by the bounding box to center the piece on the cursor.
          grid_x := i32(math.floor((canvas_mouse_x - sx) / unit_sz))
          target_x := grid_x - (state.cur.box_sz / 2)
          for state.cur.pos.x < target_x {
            if !try_move(1, 0) do break
          }
          for state.cur.pos.x > target_x {
            if !try_move(-1, 0) do break
          }
        }
      }

      // handle verticle movement and rotations
      if pressed_hard_drop {
        drop_distance : i32 = 0
        for is_valid_placement(state.cur.pos.x, state.cur.pos.y+1, state.cur.minos[:]) {
          state.cur.pos.y += 1
          drop_distance += 1
        }
        state.score += drop_distance * SCORE_HARD_DROP
        lock_tetro()
        state.cur = pop_next()
      }
      // soft drop is handled in the tick() call

      if pressed_rot_cw do try_rotate(true);
      if pressed_rot_ccw do try_rotate(false);

      // handle horizontal movement
      first_left, first_right := rl.IsKeyPressed(.LEFT), rl.IsKeyPressed(.RIGHT)
      left_down, right_down := rl.IsKeyDown(.LEFT), rl.IsKeyDown(.RIGHT)
      if first_left {
        state.active_dir = -1
        state.das_timer_ms, state.arr_timer_ms = 0.0, 0.0
        try_move(-1, 0)
      } else if first_right {
        state.active_dir = 1
        state.das_timer_ms, state.arr_timer_ms = 0.0, 0.0
        try_move(1, 0)
      }

      is_active_key_held := (state.active_dir == -1 && left_down) || (state.active_dir == 1 && right_down)
      if is_active_key_held {
        state.das_timer_ms += dt_ms
        if state.das_timer_ms >= state.config.das_ms {
          state.arr_timer_ms += dt_ms
          for state.arr_timer_ms >= state.config.arr_ms {
            try_move(state.active_dir, 0)
            state.arr_timer_ms -= state.config.arr_ms
          }
        }
      } else {
        state.active_dir = 0
        // check if the inactive direction is being held
        if left_down {
          state.active_dir = -1
          state.das_timer_ms = state.config.das_ms
        } else if right_down {
          state.active_dir = 1
          state.das_timer_ms = state.config.das_ms
        }
      }

      // handle holding swap
      if pressed_hold {
        if !state.hold_locked {
          if state.is_holding_tetro {
            state.hold, state.cur = TETROS[state.cur.type], state.hold
          } else {
            state.hold = TETROS[state.cur.type]
            state.cur = pop_next()
            state.is_holding_tetro = true
          }
          state.hold_locked = true
          state.cur.accum_y = 0.0
          state.cur.lock_timer_ms = 0.0
        }
      }

      tick(dt_s, dt_ms, holding_soft_drop)
    }

    // handle zoom in and zoom out
    if rl.IsKeyPressed(.MINUS) {
      state.zoom = max(0.25, state.zoom - 0.25)
    } else if rl.IsKeyPressed(.EQUAL) {
      state.zoom = min(4.0, state.zoom + 0.25)
    }

    // first pass drawing (render to canvas)
    rl.BeginTextureMode(target)
    rl.ClearBackground(BG_COLOR)

    render_ui()
    render_playfield()
    if state.config.show_ghost {
      render_ghost(&state.cur)
    }
    render_tetro(&state.cur)

    if state.config.show_all_ui {
      dbg_tetros := TETROS
      for &t, i in dbg_tetros {
        idx := i32(i)
        t.pos = {(idx<4?12:17), i32((idx<4?idx*3:(idx-3)*3))+12}
        render_tetro(&t)
      }
    }

    if state.mode == .MENU {
      render_menu()
    }

    rl.EndTextureMode()

    // second pass drawing (scale canvas to screen)
    source_rec := rl.Rectangle{0, 0, target_w, -target_h}
    dst_rec := rl.Rectangle{ x = dst_rec_x, y = dst_rec_y, width = target_w * scale, height = target_h * scale }

    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)
    rl.DrawTexturePro(target.texture, source_rec, dst_rec, {0, 0}, 0.0, rl.WHITE)
    rl.EndDrawing()
  }
}
