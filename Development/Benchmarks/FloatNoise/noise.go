package main

import "os"

func fade(v float64) float64 { return v*v*v*(v*(v*6.0-15.0)+10.0) }
func noise(x, y, z float64) float64 {
	xy, yz, zx := x*y, y*z, z*x
	u, v, w := fade(x), fade(y), fade(z)
	first, second, third := xy+yz, yz+zx, zx+xy
	return (first*(1.0-u)+second*u)*(1.0-w)+third*w+v
}
func main() {
	total, x := 0.0, 0.37
	for i := 0; i < 1000000; i++ { total += noise(x, 0.61, 0.23); x += 0.00001 }
	if total > 0.0 { os.Exit(1) }
}
