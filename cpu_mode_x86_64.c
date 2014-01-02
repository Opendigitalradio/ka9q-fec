/* Determine CPU support for SIMD
 * Copyright 2004 Phil Karn, KA9Q
 *
 * Modified in 2012 by Matthias P. Braendli, HB9EGM
 */
#include <stdio.h>
#include "fec.h"

/* Various SIMD instruction set names */
char *Cpu_modes[] = {"Unknown","Portable C","x86 Multi Media Extensions (MMX)",
		   "x86 Streaming SIMD Extensions (SSE)",
		   "x86 Streaming SIMD Extensions 2 (SSE2)",
		   "PowerPC G4/G5 Altivec/Velocity Engine"};

enum cpu_mode Cpu_mode;

void find_cpu_mode(void){

  int f;
  if(Cpu_mode != UNKNOWN)
    return;

  /* According to the wikipedia entry x86-64, all x86-64 processors have SSE2 */
  /* The same assumption is also in other source files ! */
  Cpu_mode = SSE2;
  fprintf(stderr,"CPU: x86-64, using portable C implementation\n");
}
