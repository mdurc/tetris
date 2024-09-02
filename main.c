#include <assert.h>
#include <raylib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

//------------------------------------------------------------------------------------
// Definitions
//------------------------------------------------------------------------------------
#define SQUARE_SIZE 30

#define GRID_VERTICAL_SIZE 20
#define GRID_HORIZONTAL_SIZE 13

typedef enum Square { EMPTY, TAKEN, FALLING, CLEARING} Square;

static uint32_t window_width = 900;
static uint32_t window_height = 850;

// For simulating gravity over time
static uint32_t gravity_count = 0;
static uint32_t gravity = 30;

static uint32_t clear_line_count = 0;
static uint32_t clearing_time = 15;

static uint8_t filled_lines = 0;
static uint8_t filled_rows[4];

// TODO
static Color fading_color = (Color){255, 255, 255, 255};

static int32_t frame = 0;

// Whether or not the pieces place immedieatly or after a delay when hitting the bottom or another piece
static int8_t add_lock_delay = 1;

//------------------------------------------------------------------------------------
// Game Structure
//------------------------------------------------------------------------------------
typedef struct Game {
    Square grid[GRID_VERTICAL_SIZE][GRID_HORIZONTAL_SIZE];
    Square piece[4][4];
    Square next_piece[4][4];
    Square held_piece[4][4];

    uint8_t curr_piece_type;
    int32_t curr_piece_x;
    int32_t curr_piece_y;
    uint8_t stop_moving_down;
    uint8_t holding_piece;

    uint8_t game_over;
    uint8_t pause;

    uint32_t level;
    uint32_t lines;
} Game;

//------------------------------------------------------------------------------------
// Function Prototypes
//------------------------------------------------------------------------------------
void InitializeGame(Game* game);
void UpdateGame(Game* game);
void DrawGame(const Game* const game);
void GeneratePiece(Game* game, Square p[4][4]);
void SetPieceInGrid(Game* game, int8_t type);

int8_t IsFilledRow(Game* game, int8_t row, enum Square state);
int8_t CheckPieceCollision(Game* game, int8_t dx, int8_t dy);
int8_t AttemptRotation(Game* game);
void RotatePiece(Game* game);
void CopyPieceFromTo(Square a[4][4], Square b[4][4]);

//------------------------------------------------------------------------------------
// Entry Point
//------------------------------------------------------------------------------------
int main(void) {
    srand(time(NULL));

    Game game;
    InitializeGame(&game);

    SetTraceLogLevel(LOG_ERROR);
    InitWindow(window_width, window_height, "tetris");
    SetTargetFPS(60);

    while (!WindowShouldClose()) {
        UpdateGame(&game);

        BeginDrawing();

        ClearBackground((Color){20, 20, 20, 255});
        DrawGame(&game);

        EndDrawing();
    }

    CloseWindow();
    return 0;
}

//------------------------------------------------------------------------------------
// Function Definitions
//------------------------------------------------------------------------------------
void InitializeGame(Game* game) {
    uint8_t i, j;
    game->curr_piece_type = -1; // No current piece yet
    game->curr_piece_x = GRID_HORIZONTAL_SIZE/2;
    game->curr_piece_y = -1; // Make starting piece location to be flush with the top of grid. Check piece layouts.
    game->stop_moving_down = 0;
    game->holding_piece = 0;
    game->game_over = 0;
    game->pause = 0;
    game->level = 1;
    game->lines = 0;

    for (i = 0; i < GRID_VERTICAL_SIZE; ++i) {
        for (j = 0; j < GRID_HORIZONTAL_SIZE; ++j) {
            if(i<4 && j<4){
                game->piece[i][j] = EMPTY;
                game->next_piece[i][j] = EMPTY;
                game->held_piece[i][j] = EMPTY;
            }
            game->grid[i][j] = EMPTY;
        }
    }

    GeneratePiece(game, game->piece);
    // TODO: show the next piece in the corner of the ui
    ++frame;
    GeneratePiece(game, game->next_piece);
}

void UpdateGame(Game* game) {
    // don't update game if it is game over
    if(game->game_over) return;

    ++frame;

    int8_t i,j,k;

    // Update the counters
    ++gravity_count;
    ++clear_line_count;

    // Check if the current piece is going to land on another piece
    if(CheckPieceCollision(game, 0, 1) || game->curr_piece_y == (GRID_VERTICAL_SIZE-1)){
        if(add_lock_delay) game->stop_moving_down = 1;
        // Wait until gravity would make it collide before placing it
        // Going to collide with something on the bottom
        if(!add_lock_delay || gravity_count >= gravity){
            // Set the piece
            SetPieceInGrid(game, 1);

            // Check if a line clear has occurred, update game stats
            for(i=0; i<GRID_VERTICAL_SIZE; ++i){

                // Check if the line is full of TAKEN's 
                if(IsFilledRow(game, i, TAKEN)){
                    assert((filled_lines+1)<=4);
                    filled_rows[filled_lines++] = i;
                    // clear this line
                    clear_line_count = 0;
                    ++game->lines;
                    if(game->lines%10 == 0){
                        if(++game->level > 5){ // 50 ines
                            add_lock_delay = 0; // no more delay to place blocks
                        }
                        gravity-=2;
                    }
                    for(k=0;k<GRID_HORIZONTAL_SIZE;++k){
                        game->grid[i][k] = CLEARING;
                    }
                }
            }

            CopyPieceFromTo(game->next_piece, game->piece);
            GeneratePiece(game, game->next_piece);

            // TODO: make random spawn locations
            game->curr_piece_x = GRID_HORIZONTAL_SIZE/2;

            // Spawn at the top (shape may not start at 0,0 of piece shape)
            game->stop_moving_down = 0;
            game->curr_piece_y = -1;
            if(CheckPieceCollision(game, 0, 0)){
                game->game_over = 1;
                printf("Game Over\n");

                // show the piece that caused the game over:
                SetPieceInGrid(game, 1);
                return;
            }

            gravity_count = 0;
        }
    }

    // Clear levels
    if(filled_lines>0 && clear_line_count>=clearing_time){
        clear_line_count = 0;
        // Make all squares that are being cleared, now empty
        for(i=0; i<filled_lines; ++i){
            for(j=0; j<GRID_HORIZONTAL_SIZE; ++j){
                assert(filled_rows[i] >= 0 && filled_rows[i] < GRID_VERTICAL_SIZE);
                assert(j >= 0 && j < GRID_VERTICAL_SIZE);
                assert(game->grid[filled_rows[i]][j] == CLEARING);
                game->grid[filled_rows[i]][j] = EMPTY;
            }
        }
        filled_lines = 0;

        // FALLING ROWS AFTER CLEAR: =======
        // If the line below a piece is fully empty, fall down.
        for(i = GRID_VERTICAL_SIZE - 2; i >= 0; --i) {
            // check if the entire row below is empty
            int8_t row_underneath = i+1;
            while(row_underneath <= (GRID_VERTICAL_SIZE-1) && IsFilledRow(game, row_underneath, EMPTY) && !IsFilledRow(game,row_underneath-1,EMPTY)){
                for(j = 0; j < GRID_HORIZONTAL_SIZE; ++j) {
                    // only move down if it is taken
                    if(game->grid[row_underneath-1][j] == TAKEN){
                        game->grid[row_underneath][j] = game->grid[row_underneath-1][j];
                        game->grid[row_underneath-1][j] = EMPTY;
                    }
                }
                ++row_underneath;
            }
        }
    }

    if(IsKeyPressed(KEY_C)){
        // Either swap with the currently held piece, or save this piece
        SetPieceInGrid(game, 0);
        if(game->holding_piece){
            // swap
            Square temp[4][4];
            CopyPieceFromTo(game->piece, temp);
            CopyPieceFromTo(game->held_piece, game->piece);
            CopyPieceFromTo(temp, game->held_piece);
        }else{
            // save current piece
            game->holding_piece = 1;
            CopyPieceFromTo(game->piece, game->held_piece);
            CopyPieceFromTo(game->next_piece, game->piece);
            GeneratePiece(game, game->next_piece);
        }
    }

    // Piece rotation
    if(IsKeyPressed(KEY_UP) && AttemptRotation(game)){
        SetPieceInGrid(game, 0);
        RotatePiece(game);
    }

    // Erase old location before applying gravity or moving
    // Dont have to check bounds because stop_moving_down will toggle when there is a piece or wall beneath the block.
    // Or if add_lock_delay is false, the block will have already solidified if it was unable to move down any more.
    if(!game->stop_moving_down){
        if(gravity_count >= gravity){
            SetPieceInGrid(game, 0);
            ++game->curr_piece_y;
            gravity_count = 0;
        } else if(IsKeyDown(KEY_DOWN)){
            SetPieceInGrid(game, 0);
            ++game->curr_piece_y;
        } else if(IsKeyPressed(KEY_SPACE)){
            // Instantly fall
            SetPieceInGrid(game, 0);
            while(!CheckPieceCollision(game, 0, 1)){
                ++game->curr_piece_y;
            }
            // So that it places automatically on next frame, despite add_lock_delay
            gravity_count = gravity;
        }
    }

    // Check for keyboard input, horizontal movement
    if(IsKeyPressed(KEY_LEFT) && !CheckPieceCollision(game, -1, 0)){
        game->stop_moving_down = 0;
        SetPieceInGrid(game, 0);
        --game->curr_piece_x;
    }
    if(IsKeyPressed(KEY_RIGHT) && !CheckPieceCollision(game, 1, 0)){
        game->stop_moving_down = 0;
        SetPieceInGrid(game, 0);
        ++game->curr_piece_x;
    }
    
    // Set falling piece
    SetPieceInGrid(game, 2);
}

void DrawGame(const Game* game) {
    uint8_t i,j;
    uint32_t offset_y = (window_height - GRID_VERTICAL_SIZE*SQUARE_SIZE)/2;
    uint32_t offset_x = (window_width - GRID_HORIZONTAL_SIZE*SQUARE_SIZE)/2;

    // DRAW ALL SQUARES
    for(i=0;i<GRID_VERTICAL_SIZE;++i){
        for(j=0;j<GRID_HORIZONTAL_SIZE;++j){
            if(game->grid[i][j] == TAKEN){
                DrawRectangle(j*SQUARE_SIZE + offset_x, i*SQUARE_SIZE + offset_y, SQUARE_SIZE, SQUARE_SIZE, BLUE); 
            } else if(game->grid[i][j] == FALLING){
                DrawRectangle(j*SQUARE_SIZE + offset_x, i*SQUARE_SIZE + offset_y, SQUARE_SIZE, SQUARE_SIZE, LIGHTGRAY); 
            } else if(game->grid[i][j] == CLEARING){
                DrawRectangle(j*SQUARE_SIZE + offset_x, i*SQUARE_SIZE + offset_y, SQUARE_SIZE, SQUARE_SIZE, RED); 
            }

        }
    }

    // DRAWING THE GRID LAST
    for(i=0;i<=GRID_HORIZONTAL_SIZE;++i){
        // Vertical lines
        DrawLine(i*SQUARE_SIZE + offset_x, offset_y, i*SQUARE_SIZE + offset_x, GRID_VERTICAL_SIZE*SQUARE_SIZE + offset_y, MAROON);
    }
    for(i=0;i<=GRID_VERTICAL_SIZE;++i){
        // Horizontal lines
        DrawLine(offset_x, i*SQUARE_SIZE + offset_y, GRID_HORIZONTAL_SIZE*SQUARE_SIZE + offset_x, i*SQUARE_SIZE + offset_y, MAROON);
    }

    // DRAWING THE "Next Piece" Showcase
    for(i=0; i<4; ++i){
        for(j=0; j<4; ++j){
            if(game->next_piece[i][j] == FALLING){
                DrawRectangle((j*SQUARE_SIZE + GRID_HORIZONTAL_SIZE*SQUARE_SIZE + offset_x+SQUARE_SIZE), i*SQUARE_SIZE + offset_y, SQUARE_SIZE, SQUARE_SIZE, LIGHTGRAY);
            }
        }
    }

    // DRAWING THE "Held Piece" Showcase
    for(i=0; i<4; ++i){
        for(j=0; j<4; ++j){
            if(game->held_piece[i][j] == FALLING){
                DrawRectangle(offset_x - SQUARE_SIZE*2 - j*SQUARE_SIZE, i*SQUARE_SIZE + offset_y, SQUARE_SIZE, SQUARE_SIZE, LIGHTGRAY);
            }
        }
    }

    // DRAWING GAME STATS
    int32_t stat_font_size = SQUARE_SIZE*(2/3.0f);
    DrawText(TextFormat("Level: %d", game->level), 
             window_width - MeasureText(TextFormat("Level: %d", game->level), stat_font_size) - offset_x, 
             offset_y-SQUARE_SIZE, stat_font_size, DARKGRAY);

    DrawText(TextFormat("Lines: %d", game->lines), offset_x, offset_y-SQUARE_SIZE, stat_font_size, DARKGRAY);


    if(game->game_over){
        int32_t width = SQUARE_SIZE*10;
        int32_t height = SQUARE_SIZE*5;
        int32_t font_size = SQUARE_SIZE + SQUARE_SIZE/3;
        DrawRectangle((window_width - width) / 2, (window_height - height) / 2, width, height, DARKGRAY);

        DrawText("GAME OVER", 
                (window_width - MeasureText("GAME OVER", font_size)) / 2, 
                (window_height - height) / 2 + (height - font_size) / 2, 
                font_size, RAYWHITE);
    }
}


void GeneratePiece(Game* game, Square p[4][4]){
    int8_t i,j;
    int8_t index = rand() % 7;
    while(index == game->curr_piece_type){
        index = rand() % 7;
    }
    game->curr_piece_type = index;
    // 6 different piece shapes. 2 is where the FALLING piece is
    Square opts[7][4][4] = {
        // Rod
        {{0, 0, 0, 0},
         {2, 2, 2, 2},
         {0, 0, 0, 0},
         {0, 0, 0, 0}},
        // Square
        {{0, 0, 0, 0},
         {0, 2, 2, 0},
         {0, 2, 2, 0},
         {0, 0, 0, 0}},
        // L
        {{0, 0, 0, 0},
         {2, 2, 2, 0},
         {0, 0, 2, 0},
         {0, 0, 0, 0}},
        // Backwards L
        {{0, 0, 0, 0},
         {2, 2, 2, 0},
         {2, 0, 0, 0},
         {0, 0, 0, 0}},
        // Upwards Z
        {{0, 0, 0, 0},
         {0, 2, 2, 0},
         {2, 2, 0, 0},
         {0, 0, 0, 0}},
        // Plus
        {{0, 0, 0, 0},
         {2, 2, 2, 0},
         {0, 2, 0, 0},
         {0, 0, 0, 0}},
        // Downwards Z
        {{0, 0, 0, 0},
         {2, 2, 0, 0},
         {0, 2, 2, 0},
         {0, 0, 0, 0}},
    };

    CopyPieceFromTo(opts[index], p);
}


// Return 0 for no collisions
// Return 1 for block collisions
// Return 2 for border collisions
int8_t CheckPieceCollision(Game* game, int8_t dx, int8_t dy){
    // TODO: introduce logic here
    int32_t x = game->curr_piece_x;
    int32_t y = game->curr_piece_y;

    int8_t i,j;
    int8_t found_taken = 0;
    for(i=0;i<4;++i){
        for(j=0;j<4;++j){
            // Only check the components of piece that are falling
            if(game->piece[i][j] != FALLING) continue;

            if(((j+x+dx) >= 0 && (j+x+dx) < GRID_HORIZONTAL_SIZE) &&
                    ((i+y+dy) >= 0 && (i+y+dy) < GRID_VERTICAL_SIZE)){
                switch(game->grid[i+y+dy][j+x+dx]){
                    case TAKEN:
                    case CLEARING:
                        found_taken = 1;
                        break;

                    case EMPTY:
                    case FALLING:
                    default:
                        continue;
                }
            }else{
                found_taken = 2;
                break;
            }
        }
        if(found_taken) break;
    }

    // Outside of bounds or found a taken spot
    return found_taken;
}


// types -> 0:EMPTY, 1:TAKEN, 2: FALLING, 
void SetPieceInGrid(Game* game, int8_t type){
    int8_t i,j;
    int8_t x,y;
    for(i=0;i<4;++i){
        for(j=0;j<4;++j){
            if(game->piece[i][j] != FALLING) continue;

            x = game->curr_piece_x + j;
            y = game->curr_piece_y + i;
            if((y >= 0 && y < GRID_VERTICAL_SIZE) && (x >= 0 && x < GRID_HORIZONTAL_SIZE)){
                game->grid[y][x] =
                    type == 0 ? EMPTY : type == 1 ? TAKEN : FALLING;
            }
        }
    }
}



// Automatically rotate clockwise
int8_t AttemptRotation(Game* game){
    // Save current orientation and attempt a rotation and check for collisions
    int8_t i,j, ret;
    Square temp[4][4];
    CopyPieceFromTo(game->piece, temp);
    RotatePiece(game);

    if(CheckPieceCollision(game,0,0) != 0){
        // INVALID ROTATION
        ret = 0;
    }else{
        // VALID ROTATION
        ret = 1;
    }

    // revert attempt
    CopyPieceFromTo(temp, game->piece);
    return ret;
}

void RotatePiece(Game* game){
    int8_t i, j;
    Square rotated[4][4];

    for (i = 0; i < 4; ++i) {
        for (j = 0; j < 4; ++j) {
            rotated[i][j] = game->piece[3 - j][i];
        }
    }

    CopyPieceFromTo(rotated, game->piece);
}


int8_t IsFilledRow(Game* game, int8_t row, enum Square state){
    assert(row < GRID_VERTICAL_SIZE);
    int8_t i;
    for(i = 0; i < GRID_HORIZONTAL_SIZE; ++i) {
        if(game->grid[row][i] != state) {
            return 0;
        }
    }
    return 1;
}

void CopyPieceFromTo(Square a[4][4], Square b[4][4]){
    int8_t i, j;
    for (i = 0; i < 4; ++i) {
        for (j = 0; j < 4; ++j) {
            b[i][j] = a[i][j];
        }
    }
}
