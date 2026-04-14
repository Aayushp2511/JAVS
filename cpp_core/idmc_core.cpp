#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

/**
 * Centipede Graph Structure (Pn \odot 2k1)
 * This structure represents the key space.
 * The 'seed' dictates the arrangement of indices in the graph.
 */
typedef struct {
    int32_t n;
    int32_t* path_labels;
    int32_t* pendant_labels;
} CentipedeGraph;

/**
 * Proposition 1 Vertex Labeling
 * Omega(vi) = floor(i/2)
 */
inline int32_t Omega(int32_t index) {
    return index / 2;
}

inline uint8_t normalize_mod(int32_t value, uint32_t mod) {
    int32_t normalized = value % static_cast<int32_t>(mod);
    if (normalized < 0) {
        normalized += static_cast<int32_t>(mod);
    }
    return static_cast<uint8_t>(normalized);
}

/**
 * Build a Centipede Graph based on a 512-bit seed.
 * The seed is treated as an array of 64 int8_t or similar.
 * For simplicity in FFI, we assume seed is 512 indices or a bitset.
 */
EXPORT void* build_centipede_graph(int32_t n, int32_t* seed_indices) {
    CentipedeGraph* graph = (CentipedeGraph*)malloc(sizeof(CentipedeGraph));
    graph->n = n;
    graph->path_labels = (int32_t*)malloc(sizeof(int32_t) * n);
    graph->pendant_labels = (int32_t*)malloc(sizeof(int32_t) * 2 * n);

    // Reconstruct labels based on seed-dictated positions
    for (int i = 0; i < n; i++) {
        graph->path_labels[i] = Omega(seed_indices[i]);
    }
    for (int i = 0; i < 2 * n; i++) {
        graph->pendant_labels[i] = Omega(seed_indices[n + i]);
    }

    return (void*)graph;
}

EXPORT void free_graph(void* graph_ptr) {
    CentipedeGraph* graph = (CentipedeGraph*)graph_ptr;
    if (graph) {
        free(graph->path_labels);
        free(graph->pendant_labels);
        free(graph);
    }
}

/**
 * Core Encryption Logic
 * Cv = (Pv - VL) mod M
 */
EXPORT void idmc_encrypt(uint8_t* data, int32_t length, int32_t* labels, int32_t label_count, uint32_t mod) {
    for (int i = 0; i < length; i++) {
        int32_t vl = labels[i % label_count];
        data[i] = normalize_mod(static_cast<int32_t>(data[i]) - vl, mod);
    }
}

EXPORT void idmc_decrypt(uint8_t* data, int32_t length, int32_t* labels, int32_t label_count, uint32_t mod) {
    for (int i = 0; i < length; i++) {
        int32_t vl = labels[i % label_count];
        data[i] = normalize_mod(static_cast<int32_t>(data[i]) + vl, mod);
    }
}

}
