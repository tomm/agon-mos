#include "vec.h"
#include "defines.h"
#include <string.h>

#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

void vec_init(Vec *v, size_t sizeof_elem)
{
	*v = (Vec) { NULL, sizeof_elem, 0, 0 };
}

void vec_free(Vec *v)
{
	umm_free(v->data);
	v->data = NULL;
}

void *vec_get(Vec *v, size_t index)
{
	return (unsigned char *)v->data + (index * v->elem_size);
}

void vec_set(Vec *v, size_t index, const void *elem)
{
	memcpy(vec_get(v, index), elem, v->elem_size);
}

bool vec_resize(Vec *v, size_t num_elems)
{
	void *new_data = umm_realloc(v->data, num_elems * v->elem_size);
	if (!new_data) {
		return false;
	}
	v->data = new_data;
	v->elems_allocd = num_elems;
	v->len = MIN(v->len, num_elems);
	return true;
}

/* Returns false if out of memory. */
static bool _grow(Vec *v, int num_new_elems)
{
	int elems_free = v->elems_allocd - v->len;

	if (v->data == NULL) {
		// printf("Growing from %ld to %d\n", v->elems_allocd, num_new_elems);
		v->data = umm_malloc(MAX(16, num_new_elems) * v->elem_size);
		if (!v->data) {
			return false;
		}
		v->elems_allocd = num_new_elems;
	} else if (elems_free < num_new_elems) {
		int new_size = MAX(v->elems_allocd + num_new_elems, v->elems_allocd * 2);
		// printf("Growing from %ld to %d\n", v->elems_allocd, new_size);
		void *new_data = umm_realloc(v->data, new_size * v->elem_size);
		if (!new_data) {
			return false;
		}
		v->data = new_data;
		v->elems_allocd = new_size;
	}
	return true;
}

bool vec_concat(Vec *v, const void *elems, size_t num_elems)
{
	if (!_grow(v, num_elems)) {
		return false;
	}
	memcpy(vec_get(v, v->len), elems, v->elem_size * num_elems);
	v->len += num_elems;
	return true;
}

bool vec_push(Vec *v, const void *elem)
{
	if (!_grow(v, 1)) {
		return false;
	}
	vec_set(v, v->len, elem);
	v->len++;
	return true;
}

void vec_pop(Vec *v, void *popped)
{
	kassert(v->len > 0);
	v->len--;
	if (popped) memcpy(popped, vec_get(v, v->len), v->elem_size);
}

void vec_zero(Vec *v)
{
	v->len = 0;
}
