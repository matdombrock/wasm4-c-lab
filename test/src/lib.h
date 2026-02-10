#pragma once
#include "wasm4.h"

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef float f32;
typedef u8 bool;
#define true 1
#define false 0

static const u32 palette_og[] = {0x000000, 0x555555, 0xAAAAAA, 0xFFFFFF};

void palette_setup(const u32 *pal) {
  PALETTE[0] = pal[0];
  PALETTE[1] = pal[1];
  PALETTE[2] = pal[2];
  PALETTE[3] = pal[3];
}
