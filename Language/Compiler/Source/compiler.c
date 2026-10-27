/* Compiler driver: compile source directories, with parser and literal probes. */
#define _XOPEN_SOURCE 700
#include "compiler.h"
#include "parser.h"
#include "graph.h"
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    const char **paths;
    size_t count;
    size_t capacity;
} Sources;

static int sourceError(const char *path)
{
    fprintf(stderr, "cannot load %s: %s\n", path, strerror(errno));
    return 0;
}

static int collectSources(RangeArena *arena, Sources *sources, const char *path, int nested)
{
    struct stat info;
    if (lstat(path, &info) != 0) return sourceError(path);
    int link = S_ISLNK(info.st_mode);
    if (link && stat(path, &info) != 0) return sourceError(path);
    if (S_ISDIR(info.st_mode)) {
        /* An explicitly supplied directory may be a symlink; recursive traversal
         * does not follow directory symlinks, which can lead outside Core or cycle. */
        if (nested && link) return 1;
        DIR *directory = opendir(path);
        if (!directory) return sourceError(path);
        int ok = 1;
        for (;;) {
            errno = 0;
            struct dirent *entry = readdir(directory);
            if (!entry) {
                if (errno) ok = sourceError(path);
                break;
            }
            if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
            size_t length = strlen(path) + strlen(entry->d_name) + 2;
            char *child = malloc(length);
            if (!child) abort();
            snprintf(child, length, "%s/%s", path, entry->d_name);
            ok = collectSources(arena, sources, child, 1);
            free(child);
            if (!ok) break;
        }
        closedir(directory);
        return ok;
    }
    if (!S_ISREG(info.st_mode)) {
        if (nested) return 1;
        fprintf(stderr, "cannot load %s: expected a regular file or directory\n", path);
        return 0;
    }
    size_t length = strlen(path);
    if (nested && (length < 6 || strcmp(path + length - 6, ".range"))) return 1;
    char *resolved = realpath(path, NULL);
    if (!resolved) return sourceError(path);
    if (sources->count == sources->capacity) {
        size_t capacity = sources->capacity ? sources->capacity * 2 : 16;
        const char **paths = realloc(sources->paths, capacity * sizeof(*paths));
        if (!paths) abort();
        sources->paths = paths;
        sources->capacity = capacity;
    }
    sources->paths[sources->count++] = rangeArenaIntern(arena, resolved, strlen(resolved));
    free(resolved);
    return 1;
}

static int comparePaths(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static char *readFile(const char *path, size_t *size)
{
    FILE *stream = fopen(path, "rb");
    if (!stream) return NULL;
    if (fseek(stream, 0, SEEK_END) != 0) { fclose(stream); return NULL; }
    long length = ftell(stream);
    if (length < 0 || fseek(stream, 0, SEEK_SET) != 0) { fclose(stream); return NULL; }
    char *buffer = malloc((size_t)length + 1);
    if (!buffer) { fclose(stream); return NULL; }
    if (fread(buffer, 1, (size_t)length, stream) != (size_t)length) {
        fclose(stream); free(buffer); return NULL;
    }
    fclose(stream);
    buffer[length] = '\0';
    *size = (size_t)length;
    return buffer;
}

int main(int argc, char **argv)
{
    RangeArena arena;
    rangeArenaInit(&arena);
    int treeMode = 0, asWritten = 0;
    const char *literalMacro = NULL, *literalInput = NULL;
    int first = 1;
    int option = first;
    if (argc > option + 2 && strcmp(argv[option],"--match-literal") == 0) {
        literalMacro=argv[option + 1]; literalInput=argv[option + 2]; first=option + 3;
    }
    else if (argc > option && strcmp(argv[option], "--tree") == 0) { treeMode = 1; first = option + 1; }
    else if (argc > option && strcmp(argv[option],"--as-written") == 0) { asWritten = 1; first = option + 1; }
    const char *output = "a.out";
    if (!treeMode && !literalMacro && argc > first + 1 && strcmp(argv[first],"-o") == 0) { output = argv[first + 1]; first += 2; }
    if (first >= argc) { fprintf(stderr, "usage: compiler [--as-written] [-o executable | --tree | --match-literal macro text] files-or-directories...\n"); return 64; }
    Sources sources = {0};
    RangeNode **units = NULL;
    int status = 66;
    rangeGraphInitTypes(&arena);
    if (argv[first][0] == '-') { fprintf(stderr,"unsupported option: %s\n",argv[first]); status=64; goto cleanup; }
    for (int index = first; index < argc; ++index) {
        if (!collectSources(&arena, &sources, argv[index], 0)) goto cleanup;
    }
    if (!sources.count) { fprintf(stderr, "no Range sources found\n"); goto cleanup; }
    qsort(sources.paths, sources.count, sizeof(*sources.paths), comparePaths);
    size_t unique = 0;
    for (size_t index = 0; index < sources.count; ++index) {
        if (!unique || strcmp(sources.paths[index], sources.paths[unique - 1]))
            sources.paths[unique++] = sources.paths[index];
    }
    sources.count = unique;
    units = calloc(sources.count, sizeof(*units));
    if (!units) { status = 70; goto cleanup; }
    size_t unitCount = 0;
    int failures = 0;
    for (size_t index = 0; index < sources.count; ++index) {
        const char *path = sources.paths[index];
        size_t size = 0;
        char *source = readFile(path, &size);
        if (!source) { fprintf(stderr, "cannot read %s\n", path); goto cleanup; }
        char error[512];
        RangeNode *unit = rangeParseUnit(&arena, path, source, size,
                                         error, sizeof(error));
        free(source);
        if (!unit) { fprintf(stderr, "%s\n", error); failures += 1; continue; }
        units[unitCount++] = unit;
        if (treeMode) { rangeGraphWriteTree(stdout, unit, 0); continue; }
    }
    if (!treeMode && !literalMacro) {
        SourceReport report = {.arena=&arena,.units=units,.count=unitCount};
        char error[512];
        int resolved = unitCount && resolveGraphApplications(&arena,units,unitCount,error,sizeof(error));
        if (unitCount && !resolved) sourceDiagnostic(&report,NULL,0,"resolution","%s",error);
        // Build the graph, apply macros and merge their output, then resolve names.
        Typer *typer = resolved && !failures ? diagnoseMacroApplications(&report) : NULL;
        for (size_t u = 0; u < unitCount; ++u) diagnoseSourceNode(&report,NULL,units[u],0);
        diagnoseDuplicates(&report);
        for (size_t u = 0; u < unitCount; ++u) diagnoseBuiltinFunctions(&report,units[u]);
        if (typer) typeCheck(typer);
        // Native code is generated from a complete, well-typed graph only.
        int written = typer && !report.errors && emitNative(&report,typer,output,asWritten);
        if (typer) diagnoseWritten(typer);
        writeSourceDiagnostics(&report,stderr);
        if (report.errors || failures) {
            fprintf(stderr,"compilation failed: %zu errors, %zu C implementation warnings\n",report.errors+(size_t)failures,report.warnings);
            status = 65;
        } else {
            if (written) fprintf(stderr,"wrote %s; %zu C implementation warnings\n",output,report.warnings);
            else fprintf(stderr,"checked %zu sources; no entry block, so no executable was written; %zu C implementation warnings\n",unitCount,report.warnings);
            status = 0;
        }
        goto cleanup;
    }
    if (literalMacro && !failures) {
        char error[512]; int matched = 0;
        if (!matchLiteralRule(&arena,units,unitCount,literalMacro,literalInput,&matched,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error); failures += 1;
        } else printf("match=%s\n",matched ? "true" : "false");
    }
    status = failures ? 65 : 0;
cleanup:
    free(units);
    free(sources.paths);
    rangeArenaDestroy(&arena);
    return status;
}
