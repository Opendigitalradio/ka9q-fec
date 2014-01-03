/* Determine CPU support for SIMD on Power PC
 * Copyright 2004 Phil Karn, KA9Q
 * Copyright 2014 Matthias P. Braendli, HB9EGM
 */
#include <stdio.h>
#include "fec.h"

enum cpu_mode Cpu_mode;

// Use the portable code for this unknown CPU
void find_cpu_mode(void) {
  Cpu_mode = PORT;
}
