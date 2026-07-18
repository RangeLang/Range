fn fade(v: f64) -> f64 { v*v*v*(v*(v*6.0-15.0)+10.0) }
fn noise(x: f64, y: f64, z: f64) -> f64 {
    let (xy,yz,zx)=(x*y,y*z,z*x); let (u,v,w)=(fade(x),fade(y),fade(z));
    let (first,second,third)=(xy+yz,yz+zx,zx+xy);
    (first*(1.0-u)+second*u)*(1.0-w)+third*w+v
}
fn main() { let mut total=0.0; let mut x=0.37; for _ in 0..1000000 { total += noise(x,0.61,0.23); x += 0.00001; } std::process::exit(if total > 0.0 {1} else {0}); }
