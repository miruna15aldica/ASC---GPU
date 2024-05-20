#include <stdio.h>
#include <stdint.h>
#include "../include/utils.cuh"
#include <string.h>
#include <stdlib.h>
#include <inttypes.h>

// TODO: Implement function to search for all nonces from 1 through MAX_NONCE (inclusive) using CUDA Threads
// Functia pentru cautarea valorii lui nounce
__global__ void findNonce(BYTE *difficulty, BYTE *content, uint64_t *nonce) {
	// Daca nounce-ul a fost gasit deja
	if(*nonce != 0)
		return;
    BYTE copy_content[BLOCK_SIZE];
	char nonce_str[NONCE_SIZE];
    BYTE block_hash[SHA256_HASH_SIZE];
	// Identificatorul unic al threadului
    uint64_t id_thread = blockIdx.x * blockDim.x + threadIdx.x;
	// Copiem continutul blocului
    d_strcpy((char*)copy_content, (const char*)content);
    intToString(id_thread, nonce_str);
	// Adaugam nounce-ul la sfarsit
    d_strcpy((char*)copy_content + d_strlen((const char*)copy_content), nonce_str);
    // Functia de hash
	apply_sha256(copy_content, d_strlen((const char*)copy_content), block_hash, 1);
    // Daca hash-ul are dificultatea potrivita
	if (compare_hashes(block_hash, difficulty) <= 0) {
		// schimbam nounce-ul cu valoarea pe care am gasit-o
		atomicExch((unsigned long long *)nonce,(unsigned long long)id_thread);
    }
}

// Alocam memorie pe dispozitivul CUDA
void mallocsCuda(BYTE **device_difficulty, BYTE **device_content, uint64_t **device_nonce) {
    cudaMalloc((void **)device_difficulty, SHA256_HASH_SIZE);
    cudaMalloc((void **)device_content, BLOCK_SIZE);
    cudaMalloc((void **)device_nonce, sizeof(uint64_t));
}

// Eliberam memorie pe dispozitivul CUDA
void freeCuda(BYTE *device_difficulty, BYTE *device_content, uint64_t *device_nonce) {
    cudaFree(device_difficulty);
    cudaFree(device_content);
    cudaFree(device_nonce);
}

int main(int argc, char **argv) {
	BYTE hashed_tx1[SHA256_HASH_SIZE], hashed_tx2[SHA256_HASH_SIZE], hashed_tx3[SHA256_HASH_SIZE], hashed_tx4[SHA256_HASH_SIZE],
			tx12[SHA256_HASH_SIZE * 2], tx34[SHA256_HASH_SIZE * 2], hashed_tx12[SHA256_HASH_SIZE], hashed_tx34[SHA256_HASH_SIZE],
			tx1234[SHA256_HASH_SIZE * 2], top_hash[SHA256_HASH_SIZE], block_content[BLOCK_SIZE];
	BYTE block_hash[SHA256_HASH_SIZE] = "0000000000000000000000000000000000000000000000000000000000000000"; // TODO: Update
	uint64_t nonce = 0;
	size_t current_length;

	// Rezultat nounce
	char nonce_result[NONCE_SIZE];

	// Variabile pentru stocarea datelor pe CUDA
    BYTE *device_difficulty;
    BYTE *device_content;
    uint64_t *device_nonce;

	// Top hash
	apply_sha256(tx1, strlen((const char*)tx1), hashed_tx1, 1);
	apply_sha256(tx2, strlen((const char*)tx2), hashed_tx2, 1);
	apply_sha256(tx3, strlen((const char*)tx3), hashed_tx3, 1);
	apply_sha256(tx4, strlen((const char*)tx4), hashed_tx4, 1);
	strcpy((char *)tx12, (const char *)hashed_tx1);
	strcat((char *)tx12, (const char *)hashed_tx2);
	apply_sha256(tx12, strlen((const char*)tx12), hashed_tx12, 1);
	strcpy((char *)tx34, (const char *)hashed_tx3);
	strcat((char *)tx34, (const char *)hashed_tx4);
	apply_sha256(tx34, strlen((const char*)tx34), hashed_tx34, 1);
	strcpy((char *)tx1234, (const char *)hashed_tx12);
	strcat((char *)tx1234, (const char *)hashed_tx34);
	apply_sha256(tx1234, strlen((const char*)tx34), top_hash, 1);

	// prev_block_hash + top_hash
	strcpy((char*)block_content, (const char*)prev_block_hash);
	strcat((char*)block_content, (const char*)top_hash);
	current_length = strlen((char*) block_content);

	cudaEvent_t start, stop;
	startTiming(&start, &stop);

	// Alocare memorie
    mallocsCuda(&device_difficulty, &device_content, &device_nonce);

	// Transferam datele pe dispozitivul CUDA
    cudaMemcpy(device_difficulty, DIFFICULTY, SHA256_HASH_SIZE, cudaMemcpyHostToDevice);
    cudaMemcpy(device_content, block_content, BLOCK_SIZE, cudaMemcpyHostToDevice);
    cudaMemcpy(device_nonce, &nonce, sizeof(uint64_t), cudaMemcpyHostToDevice);

	// Cautam nounce-ul
	findNonce<<< 1 + MAX_NONCE / 256, 256>>>(device_difficulty, device_content, device_nonce);
    cudaMemcpy(&nonce, device_nonce, sizeof(uint64_t), cudaMemcpyDeviceToHost);
    // Convertim nonce-ul in sir de caractere + actualizam blocu;
	snprintf((char *)block_content + strlen((char*) block_content), BLOCK_SIZE - strlen((char*) block_content), "%llu", nonce);
	int len = strlen((const char *)block_content + strlen((char*) block_content))+ strlen((char*) block_content);
	// Hash actualizat	
	apply_sha256(block_content, len, block_hash, 1);

    freeCuda(device_difficulty, device_content, device_nonce);
	float seconds = stopTiming(&start, &stop);
	printResult(block_hash, nonce, seconds);

	return 0;
}
