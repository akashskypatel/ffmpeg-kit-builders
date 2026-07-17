#include <stddef.h>

typedef void *iconv_t;

extern iconv_t libiconv_open(const char *tocode, const char *fromcode);
extern size_t libiconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
extern int libiconv_close(iconv_t cd);

iconv_t iconv_open(const char *tocode, const char *fromcode) {
  return libiconv_open(tocode, fromcode);
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft) {
  return libiconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

int iconv_close(iconv_t cd) {
  return libiconv_close(cd);
}