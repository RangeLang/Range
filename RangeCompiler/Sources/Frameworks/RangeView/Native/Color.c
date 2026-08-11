#include <math.h>
#include <stdint.h>

typedef struct RangeViewLinearRGB {
    double red;
    double green;
    double blue;
} RangeViewLinearRGB;

static double rangeViewClampUnit(double value) {
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 1.0) {
        return 1.0;
    }
    return value;
}

static double rangeViewSRGBEncode(double value) {
    value = rangeViewClampUnit(value);
    if (value <= 0.0031308) {
        return 12.92 * value;
    }
    return 1.055 * pow(value, 1.0 / 2.4) - 0.055;
}

static uint8_t rangeViewByte(double value) {
    return (uint8_t)lround(rangeViewClampUnit(value) * 255.0);
}

static RangeViewLinearRGB rangeViewOKLCHToLinearRGB(
    double lightness,
    double chroma,
    double hue
) {
    const double radians = hue * 0.017453292519943295;
    const double a = chroma * cos(radians);
    const double b = chroma * sin(radians);
    const double lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b;
    const double mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b;
    const double sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b;
    const double l = lRoot * lRoot * lRoot;
    const double m = mRoot * mRoot * mRoot;
    const double s = sRoot * sRoot * sRoot;
    RangeViewLinearRGB result;
    result.red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    result.green = -0.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    result.blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    return result;
}

uint8_t rangeViewOKLCHChannel(
    double lightness,
    double chroma,
    double hue,
    double alpha,
    int32_t channel
) {
    if (channel == 3) {
        return rangeViewByte(alpha);
    }
    const RangeViewLinearRGB linear = rangeViewOKLCHToLinearRGB(lightness, chroma, hue);
    if (channel == 0) {
        return rangeViewByte(rangeViewSRGBEncode(linear.red));
    }
    if (channel == 1) {
        return rangeViewByte(rangeViewSRGBEncode(linear.green));
    }
    return rangeViewByte(rangeViewSRGBEncode(linear.blue));
}
