#ifndef VEC_H
#define VEC_H

/**
 * Vec implementation optimized for small binary size -- not using
 * per-type code generation. Cost of this is imul on indexing operations.
 * This can be avoided by casting the vector->data to your type and 
 * indexing into that.
 *
 * On DEBUG builds there is kassert bounds checking.
 */

#include <stdbool.h>
#include <stdlib.h>

typedef struct Vec Vec;

struct Vec {
	void *data;
	size_t elem_size;
	size_t elems_allocd;
	size_t len;
};

/*
 * Functions returning bool will return false on out-of-memory.
 */
extern void vec_init(Vec *v, size_t sizeof_elem);
extern void vec_free(Vec *v);
extern void *vec_get(Vec *v, size_t index);
extern void vec_set(Vec *v, size_t index, const void *elem);
extern bool vec_push(Vec *v, const void *elem) __attribute__((warn_unused_result("false indicates out-of-memory")));
extern void vec_pop(Vec *v, void *popped); // pass popped=NULL to not copy the popped value
extern bool vec_concat(Vec *v, const void *elems, size_t num_elems) __attribute__((warn_unused_result("false indicates out-of-memory")));
extern bool vec_resize(Vec *v, size_t num_elems) __attribute__((warn_unused_result("false indicates out-of-memory")));
extern void vec_zero(Vec *v);
static inline size_t vec_len(const Vec *v) { return v->len; }

#endif					   /* VEC_H */
