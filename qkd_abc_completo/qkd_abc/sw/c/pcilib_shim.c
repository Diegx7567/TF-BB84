/*******************************************************************************
 * pcilib_shim.c
 *******************************************************************************
 * QUE ES:      biblioteca C que implementa pci_read(indice) y
 *              pci_write(indice, valor) sobre el BAR de usuario del XDMA
 *              (/dev/xdma0_user) mediante mmap.
 * PARA QUE:    es el sustituto directo ("drop-in") de la pcilib.so original:
 *              el Python existente (bridge_io / FpgaFunctions) la carga por
 *              ctypes y no nota la diferencia. Un indice del bridge = una
 *              palabra de 32 bits = offset de 4*indice bytes en el BAR.
 * COMO SE USA: gcc -shared -fPIC -o pcilib.so pcilib_shim.c
 *              y en Python: ctypes.CDLL("./pcilib.so")
 * CONECTADO A: el AXI-Lite del XDMA -> puente wr/rd del reg_file (ab_top /
 *              c_top). Requiere el driver XDMA de Xilinx cargado.
 * NOTA:        si el transporte final fuera Xillybus en vez de XDMA, solo
 *              cambia DEVICE_PATH y el mecanismo (Xillybus usa read/write
 *              sobre streams, no mmap); la interfaz pci_read/pci_write se
 *              mantiene igual para el Python.
 ******************************************************************************/
#include <stdio.h>      /* fprintf: mensajes de error                        */
#include <stdint.h>     /* uint32_t: la palabra del bridge                   */
#include <fcntl.h>      /* open, O_RDWR: abrir el dispositivo                */
#include <sys/mman.h>   /* mmap: mapear el BAR a memoria de usuario          */
#include <unistd.h>     /* close                                             */

/* dispositivo del BAR de usuario del XDMA (bypass de DMA, acceso registro) */
#define DEVICE_PATH "/dev/xdma0_user"
/* tamanho a mapear: 4096 indices x 4 bytes = 16 KiB (una pagina basta,
 * mapeamos 64 KiB por holgura con la apertura del BAR tipica del XDMA)     */
#define MAP_SIZE    (64 * 1024)

static int fd = -1;                     /* descriptor del dispositivo        */
static volatile uint32_t *bar = NULL;   /* puntero al BAR mapeado; volatile   */
                                        /* impide que el compilador cachee    */
                                        /* lecturas/escrituras de registros   */

/* inicializacion perezosa: abre y mapea la primera vez que se usa           */
static int ensure_open(void)
{
    if (bar != NULL)                    /* ya esta mapeado: nada que hacer    */
        return 0;
    fd = open(DEVICE_PATH, O_RDWR | O_SYNC);   /* O_SYNC: sin cacheo         */
    if (fd < 0) {
        fprintf(stderr, "pcilib_shim: no puedo abrir %s\n", DEVICE_PATH);
        return -1;
    }
    /* mapea MAP_SIZE bytes del BAR con lectura+escritura compartidas        */
    bar = (volatile uint32_t *)mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE,
                                    MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
        fprintf(stderr, "pcilib_shim: mmap fallo\n");
        bar = NULL;
        close(fd);
        return -1;
    }
    return 0;
}

/* lee la palabra del indice dado; devuelve -1 si el dispositivo no abre     *
 * (mismo convenio de error que usaba el software original)                  */
int pci_read(int index)
{
    if (ensure_open() != 0)             /* asegura el mapeo                   */
        return -1;
    return (int)bar[index];             /* bar[i] = offset 4*i bytes: 1 lectura
                                           AXI-Lite de 32 bits al reg_file   */
}

/* escribe la palabra del indice dado; devuelve 0 (exito) o -1               */
int pci_write(int index, int value)
{
    if (ensure_open() != 0)
        return -1;
    bar[index] = (uint32_t)value;       /* 1 escritura AXI-Lite de 32 bits    */
    return 0;
}

/* liberacion opcional (el SO limpia igualmente al salir del proceso)        */
void pci_close(void)
{
    if (bar) { munmap((void *)bar, MAP_SIZE); bar = NULL; }
    if (fd >= 0) { close(fd); fd = -1; }
}
