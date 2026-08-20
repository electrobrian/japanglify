#include <cuda_runtime.h>
#include <stdio.h>

static void print_cuda_error(const char* operation, cudaError_t error) {
    fprintf(stderr, "%s failed: %s (%d)\n", operation, cudaGetErrorString(error), (int)error);
}

int main(void) {
    int device_count = 0;
    cudaError_t error = cudaGetDeviceCount(&device_count);
    if (error != cudaSuccess) {
        print_cuda_error("cudaGetDeviceCount", error);
        return 2;
    }

    printf("CUDA device count: %d\n", device_count);
    if (device_count <= 0) {
        printf("No CUDA device reported.\n");
        return 3;
    }

    for (int index = 0; index < device_count; ++index) {
        cudaDeviceProp properties;
        error = cudaGetDeviceProperties(&properties, index);
        if (error != cudaSuccess) {
            print_cuda_error("cudaGetDeviceProperties", error);
            return 4;
        }

        size_t free_bytes = 0;
        size_t total_bytes = 0;
        error = cudaSetDevice(index);
        if (error != cudaSuccess) {
            print_cuda_error("cudaSetDevice", error);
            return 5;
        }
        error = cudaMemGetInfo(&free_bytes, &total_bytes);
        if (error != cudaSuccess) {
            print_cuda_error("cudaMemGetInfo", error);
            return 6;
        }

        printf("Device %d name: %s\n", index, properties.name);
        printf("Device %d compute capability: %d.%d\n", index, properties.major, properties.minor);
        printf("Device %d totalGlobalMemBytes: %llu\n", index, (unsigned long long)properties.totalGlobalMem);
        printf("Device %d freeMemBytes: %llu\n", index, (unsigned long long)free_bytes);
        printf("Device %d memInfoTotalBytes: %llu\n", index, (unsigned long long)total_bytes);
        printf("Device %d multiProcessorCount: %d\n", index, properties.multiProcessorCount);
        printf("Device %d clockRateKHz: %d\n", index, properties.clockRate);
        printf("Device %d integrated: %d\n", index, properties.integrated);
    }

    printf("Probe completed. No deliberate device allocation was performed.\n");
    return 0;
}
