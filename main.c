#include <assert.h>
#include <math.h>
#include <raylib.h>
#include <stdint.h>
#include <stdio.h>

//------------------------------------------------------------------------------------
// Definitions
//------------------------------------------------------------------------------------
#define SQUARE_SIZE 30

#define GRID_VERTICAL_SIZE 20
#define GRID_HORIZONTAL_SIZE 13

#define LATERAL_SPEED 10
#define VERTICAL_SPEED 10

#define CLEARING_TIME 33

typedef enum Square { EMPTY, TAKEN, FALLING, CLEARING } Square;

static uint32_t window_width = 900;
static uint32_t window_height = 850;

// For simulating gravity over time
static uint32_t gravity_count = 0;
static uint32_t gravity = 30;


static Color fading_color = (Color){255, 255, 255, 255};

//------------------------------------------------------------------------------------
// Game Structure
//------------------------------------------------------------------------------------
typedef struct Game {
    Square grid[GRID_VERTICAL_SIZE][GRID_HORIZONTAL_SIZE];
    Square piece[4][4];
    Square next_piece[4][4];

    uint32_t curr_piece_x;
    uint32_t curr_piece_y;
    uint8_t stop_piece;

    uint8_t game_over;
    uint8_t pause;

    uint32_t level;
    uint32_t lines;

    uint32_t clearing_line_timer;
} Game;

//------------------------------------------------------------------------------------
// Function Prototypes
//------------------------------------------------------------------------------------
void InitializeGame(Game* game);
void UpdateGame(Game* game);
void DrawGame(const Game* const game);
void GeneratePiece(Square p[4][4]);
uint8_t CheckPieceCollision(Game* game, Square p[4][4], uint8_t x, uint8_t y, int8_t dx, int8_t dy);

//------------------------------------------------------------------------------------
// Entry Point
//------------------------------------------------------------------------------------
int main(void) {

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
    game->curr_piece_x = GRID_HORIZONTAL_SIZE/2;
    game->curr_piece_y = 0;
    game->stop_piece = 0;
    game->game_over = 0;
    game->pause = 0;
    game->level = 1;
    game->lines = 0;
    game->clearing_line_timer = 0;

    for (i = 0; i < GRID_VERTICAL_SIZE; ++i) {
        for (j = 0; j < GRID_HORIZONTAL_SIZE; ++j) {
            if(i<4 && j<4){
                game->piece[i][j] = EMPTY;
                game->next_piece[i][j] = EMPTY;
            }
            game->grid[i][j] = EMPTY;
        }
    }

    GeneratePiece(game->piece);
    GeneratePiece(game->next_piece);
}

void UpdateGame(Game* game) {

    if(game->stop_piece || game->curr_piece_y == (GRID_VERTICAL_SIZE-1)){
        game->grid[game->curr_piece_y][game->curr_piece_x] = TAKEN;

        uint8_t i,j, found_empty;

        Square* curr = &game->piece[0][0];
        Square* next = &game->next_piece[0][0];

        // Check if a line clear has occurred, update game stats
        for(i=0; i<GRID_VERTICAL_SIZE; ++i){
            found_empty = 0;
            for(j=0; j<GRID_HORIZONTAL_SIZE; ++j){
                if(game->grid[i][j] == EMPTY){
                    found_empty = 1;
                    break;
                }
            }
            if(!found_empty){
                // clear this line
                for(j=0;j<GRID_HORIZONTAL_SIZE;++j){
                    game->grid[i][j] = CLEARING;
                }
            }
        }

        // Spawn new piece (a piece is 4x4 size)
        for(i=0;i<16;++i){ *(curr+i)= *(next+i); }
        GeneratePiece(game->next_piece);
        game->curr_piece_x = GRID_HORIZONTAL_SIZE/2;
        game->curr_piece_y = 0;
        game->stop_piece = 0;
    }

    if(CheckPieceCollision(game, game->piece, game->curr_piece_x, game->curr_piece_y, 0, 1)){
        // Going to collide with something on the bottom
        game->stop_piece = 1;
        return;
    }

    // Erase old location before applying gravity or moving down
    if(game->curr_piece_y < (GRID_VERTICAL_SIZE-1) && ++gravity_count >= gravity){
        game->grid[game->curr_piece_y][game->curr_piece_x] = EMPTY;
        ++game->curr_piece_y;
        gravity_count = 0;
    } else if(IsKeyDown(KEY_DOWN) && game->curr_piece_y < (GRID_VERTICAL_SIZE-1)){
        game->grid[game->curr_piece_y][game->curr_piece_x] = EMPTY;
        ++game->curr_piece_y;
    }

    // Check for keyboard input, horizontal movement
    if(!CheckPieceCollision(game, game->piece, game->curr_piece_x, game->curr_piece_y, -1, 0) &&
        IsKeyPressed(KEY_LEFT) && game->curr_piece_x > 0){
        game->grid[game->curr_piece_y][game->curr_piece_x] = EMPTY;
        --game->curr_piece_x;
    }
    if(!CheckPieceCollision(game, game->piece, game->curr_piece_x, game->curr_piece_y, 1, 0) &&
        IsKeyPressed(KEY_RIGHT) && game->curr_piece_x < (GRID_HORIZONTAL_SIZE-1)){
        game->grid[game->curr_piece_y][game->curr_piece_x] = EMPTY;
        ++game->curr_piece_x;
    }
    
    game->grid[game->curr_piece_y][game->curr_piece_x] = FALLING;
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
}


void GeneratePiece(Square p[4][4]){
    p[0][0] = 1;
}


uint8_t CheckPieceCollision(Game* game, Square p[4][4], uint8_t x, uint8_t y, int8_t dx, int8_t dy){
    // TODO: introduce logic here
    if(((x+dx) >= 0 && (x+dx) < GRID_HORIZONTAL_SIZE) &&
        ((y+dy) >= 0 && (y+dy) < GRID_VERTICAL_SIZE)){
        return game->grid[y+dy][x+dx] == TAKEN;
    }
    return 0;
}
