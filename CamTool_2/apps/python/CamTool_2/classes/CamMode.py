
import ac
#from pynput.keyboard import Key, Controller

class CamMode(object):
    
    def __init__(self):
        self.need_f1_key_press_forcockit = False              
        self.last_cam_offset = 0
        self.lastCamMode = 6      
        self.numberOf2After0 = 0   
        self.mustFix2CamMode = False     
     #   self.keyboard = Controller()
    def pressF1(self, times):
        ac.log("pressing f1 " + str(times))
        ac.log("camera count " + str(ac.getCameraCarCount(0)))
        for i in range(times):
            ac.setCameraMode(0)

    def changeCamModeZero(self, offset, offsetFromCamMode2):
        if(self.lastCamMode != 0):
            ac.setCameraMode(0)

        numberOfF1 = 6 - self.last_cam_offset + offset
        if numberOfF1 >= 6:
            numberOfF1 -= 6
        if (self.mustFix2CamMode == True and offset != self.last_cam_offset and self.last_cam_offset == 5) or self.mustFix2CamMode == True and offset == self.last_cam_offset and offset == 5:
            numberOfF1 = offset
        #    numberOfF1 = offsetFromCamMode2 + 6
            ac.log("ffiiixx")
        #ac.log("change cam zero lastcamoffset: " + str(self.last_cam_offset) + " offset: " + str(offset) + "numberOfF1:" + str(numberOfF1))
        self.pressF1(numberOfF1)
        self.last_cam_offset = offset
        self.lastCamMode = 0
        self.mustFix2CamMode = False

    def setCockpit(self):
        ac.log("cockpit, forcef1:" + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(4,4)
            
    def setSterringWheel(self):
        ac.log("sterringwheel, forcef1:" + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(5,5)
        
    def setFreeOutside(self):
        ac.setCameraMode(5)
        self.lastCamMode = 5

    def setHelicopter(self):
        ac.setCameraMode(4)
        self.lastCamMode = 4

    def setRoof(self):
        ac.setCameraMode(2)
        ac.setCameraCar(0,0) 
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setWheel(self):
        ac.setCameraMode(2)
        ac.setCameraCar(1,0)
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setInsideCar(self):
        ac.setCameraMode(2)
        ac.setCameraCar(2,0)
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setPassenger(self):
        ac.setCameraMode(2)
        ac.setCameraCar(3,0) 
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setDriver(self):
        ac.setCameraMode(2)
        ac.setCameraCar(4,0)
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setBehind(self):
        ac.setCameraMode(2)
        ac.setCameraCar(5,0)
        self.lastCamMode = 2
        self.mustFix2CamMode = True

    def setChaseCam(self):
        ac.log("hood, chase forcef1: " + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(0,0)

    def setChaseCamFar(self):
        ac.log("chase cam far forcef1: " + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(1,1)

    def setHood(self):
        ac.log("hood, forcef1: " + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(2,2)

    def setSubjective(self):
        ac.log("subjective, forcef1: " + str(self.need_f1_key_press_forcockit))
        self.changeCamModeZero(3,3)

    def setCamtool(self):
        ac.setCameraMode(6)
        self.lastCamMode = 6