#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>

typedef struct ina {
    char current_path[128];
    char voltage_path[128];
    char name[32];
    int current;  // mA
    int voltage;  // mV
    int last;     // Flag for the last INA (for loop termination)
} ina;

// Automatically discover all INA226 devices and populate path info
void populate_ina_array(ina *inas) {
    DIR *d = opendir("/sys/class/hwmon/");
    struct dirent *dir;
    char path[256], name_buf[32];
    FILE *f;
    int idx = 0;

    while ((dir = readdir(d)) != NULL) {
        if (strncmp(dir->d_name, "hwmon", 5) != 0)
            continue;

        snprintf(path, sizeof(path), "/sys/class/hwmon/%s/name", dir->d_name);
        f = fopen(path, "r");
        if (!f) continue;

        fgets(name_buf, sizeof(name_buf), f);
        fclose(f);

        if (strncmp(name_buf, "ina", 3) == 0) {
            snprintf(inas[idx].current_path, sizeof(inas[idx].current_path),
                     "/sys/class/hwmon/%s/curr1_input", dir->d_name);
            snprintf(inas[idx].voltage_path, sizeof(inas[idx].voltage_path),
                     "/sys/class/hwmon/%s/in2_input", dir->d_name);
            snprintf(inas[idx].name, sizeof(inas[idx].name),
                     "INA%d", idx);
            inas[idx].last = 0;
            idx++;
        }
    }
    if (idx > 0) {
        inas[idx - 1].last = 1;
    }
    closedir(d);
}

void run_measurement(const char *outfile, int interval, int iterations, int verbose, int display, ina *inas) {
    FILE *out = fopen(outfile, "w");
    if (!out) {
        perror("Failed to open output file");
        return;
    }

    char buf[32];
    int i, idx;
    float total_power;

    for (i = 0; i < iterations; i++) {
        idx = 0;
        total_power = 0.0f;

        while (1) {
            FILE *f_v = fopen(inas[idx].voltage_path, "r");
            FILE *f_c = fopen(inas[idx].current_path, "r");
            if (!f_v || !f_c) {
                perror("Failed to read voltage/current");
                return;
            }

            fgets(buf, sizeof(buf), f_v);
            inas[idx].voltage = atoi(buf);
            fclose(f_v);

            fgets(buf, sizeof(buf), f_c);
            inas[idx].current = atoi(buf);
            fclose(f_c);

            float p = (inas[idx].voltage * inas[idx].current) / 1000.0f;
            total_power += p;

            if (verbose) {
                printf("[%s] Voltage = %d mV, Current = %d mA, Power = %.2f mW\n",
                       inas[idx].name, inas[idx].voltage, inas[idx].current, p);
            }

            if (inas[idx].last) break;
            idx++;
        }

        fprintf(out, "%.3f\n", total_power);
        if (display)
            printf("Total Power: %.3f mW\n", total_power);

        sleep(interval);
    }

    fclose(out);
}

int main(int argc, char *argv[]) {
    ina inas[16];  // Supports up to 16 INA devices
    populate_ina_array(inas);

    int opt;
    int interval = 1;
    int iterations = 1;
    int verbose = 0;
    int display = 0;
    char output_file[128] = "./power_log.txt";

    while ((opt = getopt(argc, argv, "t:o:vdn:")) != -1) {
        switch (opt) {
            case 't': interval = atoi(optarg); break;
            case 'o': strncpy(output_file, optarg, sizeof(output_file)); break;
            case 'v': verbose = 1; break;
            case 'd': display = 1; break;
            case 'n': iterations = atoi(optarg); break;
        }
    }

    run_measurement(output_file, interval, iterations, verbose, display, inas);
    return 0;
}
