#include "wasm4.h"
#define u8 uint8_t
#define u16 uint16_t
#define u32 uint32_t
#define i16 int16_t

// Grid dimensions
#define COLS 8
#define ROWS 8
#define GRID_HEIGHT 120
#define GRID_WIDTH 144
// Grid offsets
#define X_OFFSET 8
#define Y_OFFSET 8
// Tones per voice (0 = no tone)
#define TONES_PER 4
// Engines per voice
#define ENGINES_PER 3

// 
enum VOICES { VOICE_A, VOICE_B, VOICE_C, VOICE_D };

const u32 PAL_OG[] = {0x001105, 0x506655, 0xA0FFA5, 0xB0FFB5};

// Position struct
// Must use i16, negative values are needed for cursor wrapping
struct Pos {
  i16 x;
  i16 y;
};

struct State {
  // Cursor position
  struct Pos cursor_pos;
  // Input released flag
  u8 input_released;
  // Frame is the track position
  u16 frame;
  // Tick is the global time counter
  u32 tick;
  enum VOICES mode;
  // Grids for each voice
  u8 grid_v1[COLS * ROWS];
  u8 grid_v2[COLS * ROWS];
  u8 grid_v3[COLS * ROWS];
  u8 grid_v4[COLS * ROWS];
  // Playback settings
  u8 limit;
  u16 rate;
  // Current values for each voice
  u8 vals[4];
  // Engine selections for each voice
  u8 engines[4];
};

// NOTE: Static arrays are auto init to zero
static struct State state = {
    .cursor_pos = {0},
    .input_released = 1,
    .tick = 0,
    .frame = 0,
    .mode = 0,
    .grid_v1 = {0},
    .grid_v2 = {0},
    .grid_v3 = {0},
    .grid_v4 = {0},
    .rate = 8,
    .limit = 16, // ROWS * COLS,
    .vals = {0},
    .engines = {0},
};

// Tone data for each voice and engine
struct ToneData {
  u32 frequency;
  u8 volume;
  u32 flags;
};

// Relate duty cycles and voices to wasm4 tone flags
const u8 duty_cycles[] = {TONE_MODE1, TONE_MODE2, TONE_MODE3, TONE_MODE4};
const u8 voices[] = {TONE_PULSE1, TONE_PULSE2, TONE_TRIANGLE, TONE_NOISE};

// Create a new engine tone
struct ToneData mktone(u16 freq_start, u16 freq_end, u8 vol, u8 duty, u8 voice) {
  struct ToneData tone;
  tone.frequency = ((u32)freq_start << 16) | (u32)freq_end;
  tone.volume = vol;
  tone.flags = voices[voice] | duty_cycles[duty];
  return tone;
}

// Voice, Engine, Tone Index
struct ToneData tone_data[4][ENGINES_PER][TONES_PER - 1];

// Setup tone data
void tones_setup() {
  // Pulse 1
  tone_data[0][0][0] = mktone(261, 100 + 261, 128, 0, 0);
  tone_data[0][0][1] = mktone(392, 100 + 392, 128, 0, 0);
  tone_data[0][0][2] = mktone(440, 100 + 440, 128, 0, 0);

  tone_data[0][1][0] = mktone(261 / 2, 400 + 261, 128, 0, 0);
  tone_data[0][1][1] = mktone(400 + 261, 261 / 2, 128, 0, 0);
  tone_data[0][1][2] = mktone(440 / 2, 400 + 440, 128, 0, 0);

  tone_data[0][2][0] = mktone(220, 0, 128, 2, 0);
  tone_data[0][2][1] = mktone(310, 0, 128, 2, 0);
  tone_data[0][2][2] = mktone(410, 0, 128, 2, 0);

  // Pulse 2
  tone_data[1][0][0] = mktone(2 * 261, 100 + 261, 128, 0, 1);
  tone_data[1][0][1] = mktone(2 * 392, 100 + 392, 128, 0, 1);
  tone_data[1][0][2] = mktone(2 * 440, 100 + 440, 128, 0, 1);

  tone_data[1][1][0] = mktone(2 * 261 / 2, 400 + 261, 128, 0, 1);
  tone_data[1][1][1] = mktone(2 * 400 + 261, 261 / 2, 128, 0, 1);
  tone_data[1][1][2] = mktone(2 * 440 / 2, 400 + 440, 128, 0, 1);

  tone_data[1][2][0] = mktone(2 * 220, 0, 128, 2, 1);
  tone_data[1][2][1] = mktone(2 * 310, 0, 128, 2, 1);
  tone_data[1][2][2] = mktone(2 * 410, 0, 128, 2, 1);

  // Triangle
  tone_data[2][0][0] = mktone(4 * 261, 100 + 261, 128, 0, 2);
  tone_data[2][0][1] = mktone(4 * 392, 100 + 392, 128, 0, 2);
  tone_data[2][0][2] = mktone(4 * 440, 100 + 440, 128, 0, 2);

  tone_data[2][1][0] = mktone(4 * 261 / 2, 400 + 261, 128, 0, 2);
  tone_data[2][1][1] = mktone(4 * 400 + 261, 261 / 2, 128, 0, 2);
  tone_data[2][1][2] = mktone(4 * 440 / 2, 400 + 440, 128, 0, 2);

  tone_data[2][2][0] = mktone(4 * 220, 0, 128, 2, 2);
  tone_data[2][2][1] = mktone(4 * 310, 0, 128, 2, 2);
  tone_data[2][2][2] = mktone(4 * 410, 0, 128, 2, 2);

  // Noise
  tone_data[3][0][0] = mktone(300, 144, 128, 0, 3);
  tone_data[3][0][1] = mktone(400, 72, 128, 0, 3);
  tone_data[3][0][2] = mktone(500, 72, 128, 0, 3);

  tone_data[3][1][0] = mktone(500, 144, 128, 1, 3);
  tone_data[3][1][1] = mktone(600, 72, 128, 1, 3);
  tone_data[3][1][2] = mktone(700, 72, 128, 1, 3);

  tone_data[3][2][0] = mktone(300, 144, 128, 2, 3);
  tone_data[3][2][1] = mktone(400, 72, 128, 2, 3);
  tone_data[3][2][2] = mktone(500, 72, 128, 2, 3);
}

// Play a tone for a given voice, engine, and tone index
void tone_play(u8 voice, u8 engine, u8 tone_idx) {
  struct ToneData data = tone_data[voice][engine][tone_idx - 1];
  tone(data.frequency, state.rate, data.volume, data.flags);
}

// Set the palette colors
void palette_set(const u32 pal[4]) {
  PALETTE[0] = pal[0];
  PALETTE[1] = pal[1];
  PALETTE[2] = pal[2];
  PALETTE[3] = pal[3];
}

// Convert grid position to screen position
struct Pos cur_to_screen(struct Pos cur) {
  u8 cell_width = GRID_WIDTH / COLS;
  u8 cell_height = GRID_HEIGHT / ROWS;
  struct Pos screen_pos = {
      .x = X_OFFSET + cur.x * cell_width,
      .y = Y_OFFSET + cur.y * cell_height,
  };
  return screen_pos;
}

// Convert grid position to index
int grid_to_index(struct Pos pos) { return pos.y * COLS + pos.x; }

// Convert index to grid position
struct Pos index_to_grid(u16 index) {
  struct Pos pos = {
      .x = index % COLS,
      .y = index / COLS,
  };
  return pos;
}

// Draw a voice rectangle in a cell
void draw_voice(struct Pos pos, u8 voice, u8 val, u8 is_cur) {
  *DRAW_COLORS = 1 + val;
  u8 cwidth_q = (GRID_WIDTH / COLS) / 4;
  u8 cheight = GRID_HEIGHT / ROWS;
  u8 cheight_h = cheight / 2;
  rect(2 + pos.x + (voice * cwidth_q), pos.y + (is_cur * cheight_h),
       cwidth_q - 1, cheight_h);
}

// Integer to ASCII conversion
// Sprintf does not work in wasm4
void itoa(u32 value, char *buffer) {
  char temp[12]; // Enough for 32-bit int
  int i = 0, j = 0;
  int is_negative = 0;

  if (value == 0) {
    buffer[0] = '0';
    buffer[1] = '\0';
    return;
  }

  if (value < 0) {
    is_negative = 1;
    value = -value;
  }

  while (value != 0) {
    temp[i++] = (value % 10) + '0';
    value /= 10;
  }

  if (is_negative)
    temp[i++] = '-';

  // Reverse the string
  while (i > 0)
    buffer[j++] = temp[--i];

  buffer[j] = '\0';
}

void input() {
  u8 gamepad = *GAMEPAD1;
  if (state.input_released) {
    if (gamepad & BUTTON_UP) {
      state.cursor_pos.y -= 1;
    }
    if (gamepad & BUTTON_DOWN) {
      state.cursor_pos.y += 1;
    }
    if (gamepad & BUTTON_LEFT) {
      state.cursor_pos.x -= 1;
    }
    if (gamepad & BUTTON_RIGHT) {
      state.cursor_pos.x += 1;
    }
    // Special cases for bottom control row
    if (state.cursor_pos.y >= ROWS) {
      if (state.cursor_pos.x == 4 || state.cursor_pos.x == 6) {
        if (gamepad & BUTTON_LEFT) {
          state.cursor_pos.x -= 1;
        }
        else if (gamepad & BUTTON_RIGHT) {
          state.cursor_pos.x += 1;
        }
        else {
          state.cursor_pos.x = 5;
        }
      }
      // Bottom bounds checks
      // Bottom loops around instead of back to top
      if (state.cursor_pos.x < 0) {
        state.cursor_pos.x = ROWS - 1;
      }
      if (state.cursor_pos.x >= ROWS) {
        state.cursor_pos.x = 0;
      }
    }
    // Bounds checks
    if (state.cursor_pos.x < 0) {
      state.cursor_pos.x = COLS - 1;
      state.cursor_pos.y -= 1;
    }
    if (state.cursor_pos.x >= COLS) {
      state.cursor_pos.x = 0;
      // Special check for last real row
      // Dont move to bottom control row
      if (state.cursor_pos.y < ROWS - 1) {
        state.cursor_pos.y += 1;
      } else {
        state.cursor_pos.y = 0;
      }
    }
    if (state.cursor_pos.y < 0) {
      state.cursor_pos.y = ROWS - 1;
    }
    if (state.cursor_pos.y >= ROWS + 1) {
      state.cursor_pos.y = 0;
    }
    // Main logic
    if (state.cursor_pos.y < ROWS - 1) {
      // Mode switch
      if (gamepad & BUTTON_1) {
        state.mode = (state.mode + 1) % 4;
      }
      // Increment tone value
      if (gamepad & BUTTON_2) {
        switch (state.mode) {
        case VOICE_A:
          state.grid_v1[grid_to_index(state.cursor_pos)] += 1;
          state.grid_v1[grid_to_index(state.cursor_pos)] %= TONES_PER;
          break;
        case VOICE_B:
          state.grid_v2[grid_to_index(state.cursor_pos)] += 1;
          state.grid_v2[grid_to_index(state.cursor_pos)] %= TONES_PER;
          break;
        case VOICE_C:
          state.grid_v3[grid_to_index(state.cursor_pos)] += 1;
          state.grid_v3[grid_to_index(state.cursor_pos)] %= TONES_PER;
          break;
        case VOICE_D:
          state.grid_v4[grid_to_index(state.cursor_pos)] += 1;
          state.grid_v4[grid_to_index(state.cursor_pos)] %= TONES_PER;
          break;
        }
      }
    }
    // Control row
    else {
      // Limit control
      if (state.cursor_pos.x == 5) {
        if (gamepad & BUTTON_1) {
          state.limit += 1;
          if (state.limit > COLS * ROWS) {
            state.limit = 1;
          }
        }
        if (gamepad & BUTTON_2) {
          if (state.limit > 1) {
            state.limit -= 1;
          } else {
            state.limit = COLS * ROWS;
          }
        }
      }
      // Rate control
      if (state.cursor_pos.x == 7) {
        if (gamepad & BUTTON_1) {
          state.rate += 1;
          if (state.rate > 64) {
            state.rate = 1;
          }
        }
        if (gamepad & BUTTON_2) {
          if (state.rate > 1) {
            state.rate -= 1;
          } else {
            state.rate = 64;
          }
        }
      }
      // Engine A
      if (state.cursor_pos.x < 4) {
        if (gamepad & BUTTON_1) {
          state.engines[state.cursor_pos.x] =
              (state.engines[state.cursor_pos.x] + 1) % ENGINES_PER;
        }
        if (gamepad & BUTTON_2) {
          if (state.engines[state.cursor_pos.x] == 0) {
            state.engines[state.cursor_pos.x] = ENGINES_PER - 1;
          } else {
            state.engines[state.cursor_pos.x] -= 1;
          }
        }
      }
    }
    state.input_released = 0;
  }
  // Reset input released flag
  if (!(gamepad & (BUTTON_UP | BUTTON_DOWN | BUTTON_LEFT | BUTTON_RIGHT |
                   BUTTON_1 | BUTTON_2))) {
    state.input_released = 1;
  }
}

// Called once at the start
void start() {
  palette_set(PAL_OG);
  tones_setup();
}

// Called every frame
void update() {
  state.tick += 1;

  // Play tones
  if (state.tick % state.rate == 0) {
    state.frame += 1;
    state.frame = state.frame % state.limit;
    state.vals[0] = state.grid_v1[state.frame];
    if (state.vals[0]) {
      if (state.vals[0] > 0) {
        tone_play(0, state.engines[0], state.vals[0]);
      }
    }
    state.vals[1] = state.grid_v2[state.frame];
    if (state.vals[1]) {
      if (state.vals[1] > 0) {
        tone_play(1, state.engines[1], state.vals[1]);
      }
    }
    state.vals[2] = state.grid_v3[state.frame];
    if (state.vals[2]) {
      if (state.vals[2] > 0) {
        tone_play(2, state.engines[2], state.vals[2]);
      }
    }
    state.vals[3] = state.grid_v4[state.frame];
    if (state.vals[3]) {
      if (state.vals[3] > 0) {
        tone_play(3, state.engines[3], state.vals[3]);
      }
    }
  }

  input();

  // Render voices
  for (u8 y = 0; y < ROWS; y++) {
    for (u8 x = 0; x < COLS; x++) {
      u8 idx = y * COLS + x;
      *DRAW_COLORS = 1;
      struct Pos cell_pos = cur_to_screen((struct Pos){x, y});
      if (state.grid_v1[idx]) {
        draw_voice(cell_pos, 0, state.grid_v1[idx], 0);
      }
      if (state.grid_v2[idx]) {
        draw_voice(cell_pos, 1, state.grid_v2[idx], 0);
      }
      if (state.grid_v3[idx]) {
        draw_voice(cell_pos, 2, state.grid_v3[idx], 0);
      }
      if (state.grid_v4[idx]) {
        draw_voice(cell_pos, 3, state.grid_v4[idx], 0);
      }
    }
  }

  // Draw grid
  *DRAW_COLORS = 2;
  u8 vsplit = GRID_WIDTH / COLS;
  for (u8 i = 0; i < COLS; i++) {
    vline(X_OFFSET + i * vsplit, Y_OFFSET, GRID_HEIGHT);
  }
  // rect(79, Y_OFFSET, 3, GRID_HEIGHT);
  vline(X_OFFSET + GRID_WIDTH, Y_OFFSET, GRID_HEIGHT + 1);
  u8 hsplit = GRID_HEIGHT / ROWS;
  for (u8 i = 0; i < ROWS + 1; i++) {
    hline(X_OFFSET + 0, Y_OFFSET + i * hsplit, GRID_WIDTH);
  }

  u8 cwidth = GRID_WIDTH / COLS;
  u8 cheight = GRID_HEIGHT / ROWS;

  // Draw X on cells which are over limit
  for (u8 x = 0; x < COLS; x++) {
    for (u8 y = 0; y < ROWS; y++) {
      u8 idx = y * COLS + x;
      if (idx >= state.limit) {
        struct Pos cell_pos = cur_to_screen((struct Pos){x, y});
        *DRAW_COLORS = 2;
        rect(cell_pos.x + 2, cell_pos.y + 2, cwidth - 3, cheight - 3);
      }
    }
  }

  // Render cursor
  *DRAW_COLORS = 4;
  struct Pos cpos = cur_to_screen(state.cursor_pos);
  // Draw rectangle
  if (state.cursor_pos.y < ROWS) {
    line(cpos.x, cpos.y, cpos.x + cwidth, cpos.y);
    line(cpos.x, cpos.y, cpos.x, cpos.y + cheight);
    line(cpos.x + cwidth, cpos.y, cpos.x + cwidth, cpos.y + cheight);
    line(cpos.x, cpos.y + cheight, cpos.x + cwidth, cpos.y + cheight);
    draw_voice(cpos, (u8)state.mode, 1, 1);
  } else {
    rect(8 + state.cursor_pos.x * cwidth, 130, cwidth + 1, 3);
  }

  // Render voice info
  char buffer[12];
  *DRAW_COLORS = 1 + state.vals[0];
  rect(13, 155, 10, 3);
  *DRAW_COLORS = 2;
  text("A", 14, 135);
  itoa(state.engines[0] + 1, buffer);
  text(buffer, 14, 145);
  *DRAW_COLORS = 1 + state.vals[1];
  rect(13 + cwidth, 155, 10, 3);
  *DRAW_COLORS = 2;
  text("B", 14 + cwidth, 135);
  itoa(state.engines[1] + 1, buffer);
  text(buffer, 14 + cwidth, 145);
  *DRAW_COLORS = 1 + state.vals[2];
  rect(13 + cwidth * 2, 155, 10, 3);
  *DRAW_COLORS = 2;
  text("C", 14 + cwidth * 2, 135);
  itoa(state.engines[2] + 1, buffer);
  text(buffer, 14 + cwidth * 2, 145);
  *DRAW_COLORS = 1 + state.vals[3];
  rect(13 + cwidth * 3, 155, 10, 3);
  *DRAW_COLORS = 2;
  text("D", 14 + cwidth * 3, 135);
  itoa(state.engines[3] + 1, buffer);
  text(buffer, 14 + cwidth * 3, 145);

  // Render limit and rate info
  *DRAW_COLORS = 2;
  text("LN", 100, 135);
  itoa(state.limit, buffer);
  text(buffer, 100, 145); // Draw at (10, 10)
  text("RT", 137, 135);
  itoa(state.rate, buffer);
  text(buffer, 137, 145); // Draw at (10, 10)

  // Highlight current frame
  *DRAW_COLORS = 4;
  struct Pos cell_pos = index_to_grid(state.frame);
  struct Pos screen_pos = cur_to_screen(cell_pos);
  rect(screen_pos.x + 4, screen_pos.y + 4, cwidth - 8, cheight - 8);
}
