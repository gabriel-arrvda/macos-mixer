#ifndef CATOMICS_H
#define CATOMICS_H

#include <stdatomic.h>
#include <stdint.h>

// Acesso atômico a um uint32_t comum. Lock-free: seguro pra thread de áudio.

static inline void ca_store_u32(uint32_t *p, uint32_t value) {
    atomic_store_explicit((_Atomic uint32_t *)p, value, memory_order_relaxed);
}

static inline uint32_t ca_load_u32(const uint32_t *p) {
    return atomic_load_explicit((const _Atomic uint32_t *)p, memory_order_relaxed);
}

static inline uint32_t ca_exchange_u32(uint32_t *p, uint32_t value) {
    return atomic_exchange_explicit((_Atomic uint32_t *)p, value, memory_order_relaxed);
}

// Guarda o maior valor. Pra floats não negativos a ordem dos bits é a mesma da ordem dos números.
static inline void ca_max_u32(uint32_t *p, uint32_t value) {
    _Atomic uint32_t *a = (_Atomic uint32_t *)p;
    uint32_t current = atomic_load_explicit(a, memory_order_relaxed);
    while (value > current &&
           !atomic_compare_exchange_weak_explicit(a, &current, value, memory_order_relaxed, memory_order_relaxed)) {
    }
}

#endif
