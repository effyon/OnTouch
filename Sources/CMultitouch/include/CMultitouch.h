#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>

// Reverse-engineered layout of Apple's private MultitouchSupport.framework.
// This is the canonical struct used by open-source multitouch readers; the
// field order/sizes must match exactly or the data will be garbage.

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTReadout;

typedef struct {
    int       frame;          // frame number
    double    timestamp;      // seconds, monotonically increasing
    int       identifier;     // persistent id for a single finger contact
    int       state;          // touch phase (varies by hardware)
    int       fingerId;
    int       handId;
    MTReadout normalized;     // position & velocity, normalized 0..1 (origin bottom-left)
    float     size;           // total z / contact size (>0 while touching)
    int       zero1;
    float     angle;
    float     majorAxis;
    float     minorAxis;
    MTReadout absoluteVector; // position & velocity in mm
    int       zero2[2];
    float     zDensity;
} Finger;

typedef void *MTDeviceRef;

typedef int (*MTContactCallbackFunction)(MTDeviceRef device,
                                         Finger *touches,
                                         int numTouches,
                                         double timestamp,
                                         int frame);

CFMutableArrayRef MTDeviceCreateList(void);
MTDeviceRef       MTDeviceCreateDefault(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTContactCallbackFunction callback);
void MTDeviceStart(MTDeviceRef device, int unknown);
void MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);

#endif /* CMULTITOUCH_H */
