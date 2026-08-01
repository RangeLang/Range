declare module "d3-voronoi-map" {
  type Point = [number, number];

  export interface VoronoiMapPolygon<Datum> extends Array<Point> {
    site: {
      x: number;
      y: number;
      weight: number;
      originalObject: {
        x: number;
        y: number;
        weight: number;
        data: {
          originalData: Datum;
        };
      };
    };
  }

  interface VoronoiMapState<Datum> {
    ended: boolean;
    iterationCount: number;
    convergenceRatio: number;
    polygons: VoronoiMapPolygon<Datum>[];
  }

  interface VoronoiMapSimulation<Datum> {
    clip(polygon: Point[]): VoronoiMapSimulation<Datum>;
    weight(accessor: (datum: Datum) => number): VoronoiMapSimulation<Datum>;
    initialPosition(
      accessor: (datum: Datum, index: number, data: Datum[]) => Point,
    ): VoronoiMapSimulation<Datum>;
    convergenceRatio(ratio: number): VoronoiMapSimulation<Datum>;
    maxIterationCount(count: number): VoronoiMapSimulation<Datum>;
    prng(random: () => number): VoronoiMapSimulation<Datum>;
    stop(): VoronoiMapSimulation<Datum>;
    tick(): VoronoiMapSimulation<Datum>;
    state(): VoronoiMapState<Datum>;
  }

  export function voronoiMapSimulation<Datum>(
    data: Datum[],
  ): VoronoiMapSimulation<Datum>;
}
