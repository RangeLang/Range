@inline(__always) func fade(_ v: Double) -> Double { v*v*v*(v*(v*6.0-15.0)+10.0) }
@inline(__always) func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
    let (xy,yz,zx)=(x*y,y*z,z*x); let (u,v,w)=(fade(x),fade(y),fade(z))
    let (first,second,third)=(xy+yz,yz+zx,zx+xy)
    return (first*(1.0-u)+second*u)*(1.0-w)+third*w+v
}
var total=0.0; var x=0.37
for _ in 0..<1000000 { total += noise(x,0.61,0.23); x += 0.00001 }
exit(total > 0.0 ? 1 : 0)
import Darwin
