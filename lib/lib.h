#pragma once
#include "wasm4.h"
#include <stdlib.h>
#include <string.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef float f32;

static const u32 palette_og[] = {0x000000, 0x555555, 0xAAAAAA, 0xFFFFFF};

static inline void palette_setup(const u32 *pal) {
  PALETTE[0] = pal[0];
  PALETTE[1] = pal[1];
  PALETTE[2] = pal[2];
  PALETTE[3] = pal[3];
}

// Simple LCG parameters (Numerical Recipes)
static u32 rng_state = 1;

// Seed the RNG
static inline void rng_seed(u32 seed) {
    rng_state = seed ? seed : 1;
}

// Get the next random unsigned int
static inline u32 rng_next(void) {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}

// Get a random integer in [min, max]
static inline u32 rng_range(u32 min, u32 max) {
    if (min > max) {
        u32 tmp = min;
        min = max;
        max = tmp;
    }
    u32 r = rng_next();
    return min + (r % (max - min + 1));
}


// Simple dynamic string struct
typedef struct {
    char *data;
    size_t length;
    size_t capacity;
} String;

// Create a new string from a C-string
static inline String string_create(const char *src) {
    size_t len = strlen(src);
    String s;
    s.capacity = len + 1;
    s.data = (char*)malloc(s.capacity);
    if (s.data) {
        strcpy(s.data, src);
        s.length = len;
    } else {
        s.length = 0;
        s.capacity = 0;
    }
    return s;
}

// Free the string's memory
static inline void string_free(String *s) {
    if (s->data) free(s->data);
    s->data = NULL;
    s->length = 0;
    s->capacity = 0;
}

// Concatenate two strings, returning a new string
static inline String string_concat(const String *a, const String *b) {
    String s;
    s.length = a->length + b->length;
    s.capacity = s.length + 1;
    s.data = (char*)malloc(s.capacity);
    if (s.data) {
        strcpy(s.data, a->data);
        strcat(s.data, b->data);
    } else {
        s.length = 0;
        s.capacity = 0;
    }
    return s;
}

// Split a string by a delimiter, returning an array of strings and the count
static inline String* string_split(const String *s, char delimiter, size_t *out_count) {
    size_t count = 1;
    for (size_t i = 0; i < s->length; i++) {
        if (s->data[i] == delimiter) count++;
    }

    String *result = (String*)malloc(count * sizeof(String));
    if (!result) {
        *out_count = 0;
        return NULL;
    }

    size_t start = 0, idx = 0;
    for (size_t i = 0; i <= s->length; i++) {
        if (s->data[i] == delimiter || s->data[i] == '\0') {
            size_t part_len = i - start;
            char *part = (char*)malloc(part_len + 1);
            if (part) {
                memcpy(part, s->data + start, part_len);
                part[part_len] = '\0';
                result[idx] = string_create(part);
                free(part);
            } else {
                result[idx] = string_create("");
            }
            idx++;
            start = i + 1;
        }
    }

    *out_count = count;
    return result;
}

// Get string length
static inline size_t string_length(const String *s) {
    return s->length;
}
