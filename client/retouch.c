#include <stdlib.h>
#include <errno.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <utime.h>
#include <string.h>

void usage(char *argv0, int exval)
{
    printf( "Usage: %s [--help] [--version] <file>\n", argv0);
    exit(exval);
}

int main(int argc, char **argv)
{
    struct stat st;
    struct utimbuf ubuf;
    int i;
    char *fn = NULL;

    for (i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--help"))
            usage(argv[0], 0);

        if (!strcmp(argv[i], "--version"))
        {
            printf("%s\n", "retouch.c 1.0\n");
            exit(0);
        }

        if (fn != NULL)
            usage(argv[0], 1);

        fn = argv[i];
    }

    if (fn == NULL)
        usage(argv[0], 1);

    if (stat(fn, &st) != 0)
    {
        fprintf(stderr, "%s: error statting %s: %s\n",
                argv[0], fn, strerror(errno));
        exit(1);
    }

    ubuf.actime = st.st_atime;
    ubuf.modtime = st.st_mtime + 1;
    if (utime(fn, &ubuf) != 0)
    {
        fprintf(stderr, "%s: error setting mtime of %s: %s\n",
                argv[0], fn, strerror(errno));
        exit(1);
    }

    return 0;
}
