#include <stdio.h>
#include <stdlib.h>

static double fade(double v) { return v*v*v*(v*(v*6.0-15.0)+10.0); }
static double noise(double x, double y, double z) {
    double xy=x*y, yz=y*z, zx=z*x, u=fade(x), v=fade(y), w=fade(z);
    double first=xy+yz, second=yz+zx, third=zx+xy;
    return (first*(1.0-u)+second*u)*(1.0-w)+third*w+v;
}
int main(void) {
    double total=0.0, x=0.37;
    for (int i=0; i<1000000; ++i) { total += noise(x,0.61,0.23); x += 0.00001; }
    return total > 0.0 ? 1 : 0;
}
