#include "../src_fatfs/ff.h"
#include "defines.h"

/*
 * Used by the mos ffs API calls
 */

uint8_t fat_tell(FIL *fp, uint32_t *offset)
{
	if (fp == NULL || offset == NULL) {
		return FR_INVALID_PARAMETER;
	}
	*offset = f_tell(fp);
	return FR_OK;
}

uint8_t fat_size(FIL *fp, DWORD *size)
{
	if (fp == NULL || size == NULL) {
		return FR_INVALID_PARAMETER;
	}
	*size = f_size(fp);
	return FR_OK;
}

uint8_t fat_error(FIL *fp)
{
	return f_error(fp);
}

uint8_t fat_lseek(FIL *fp, DWORD *offset)
{
	if (fp == NULL || offset == NULL) {
		return FR_INVALID_PARAMETER;
	}
	return f_lseek(fp, *offset);
}

uint8_t fat_getfree(const TCHAR *path, DWORD *clusters, DWORD *clusterSize)
{
	FATFS *fs = NULL;
	uint8_t result;
	if (clusters == NULL || clusterSize == NULL) {
		return FR_INVALID_PARAMETER;
	}
	if (path == NULL) {
		path = ""; // Default path for our mounted drive
	}
	result = f_getfree(path, clusters, &fs);
	*clusterSize = result == FR_OK ? fs->csize : 0;
	return result;
}
