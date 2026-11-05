// Types from the private MultitouchSupport framework (macOS).
// The memory layout must match the framework exactly, which is why they are declared in C rather than Swift.
#ifndef CENTRALCLIC_BRIDGE_H
#define CENTRALCLIC_BRIDGE_H

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;       // stable finger id while it stays on the surface
    int state;            // 3 = touch starts, 4 = touching, 5 = lifting...
    int fingerID;
    int handID;
    MTReadout normalized; // position on the surface, 0..1
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout mm;
    int zero2[2];
    float unk2;
} MTFinger;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTFinger *fingers,
                                         int count, double timestamp, int frame);

#endif
