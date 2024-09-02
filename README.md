### tetris
- Simple tetris game with raylib in c

#### Features

- Classic tetris gameplay with seven different piece types
- Piece rotation
- Line clearing
- Levels and increasing difficulty
- Piece holding

#### Controls
- `Left Arrow`: Move the piece left
- `Right Arrow`: Move the piece right
- `Down Arrow`: Move the piece down faster
- `Up Arrow`: Rotate the piece clockwise
- `Spacebar`: Instantly drop the piece
- `C`: Hold the current piece or swap it with the held piece

#### Game Overview
- 10 line clears per level.
- Lock delay is removed after level 5 (50 lines).

#### Custom (optional) arguments
- `SQUARE_SIZE`: Scales all ui based on size. default is 30.

#### Build and run
- `gcc main.c -lraylib && ./a.out`
