

import math
import ac
from classes.general import normalize_angle, vec, vec3


class InterpolateFrame(object):


    def __init__(self):
        ac.log("bonjour")

    def interpolate(camtool2, locCameraData, interpolation, data, ctt, cam, dt, info, replay,strength_inv, the_x):
        if data.smart_tracking:
            cam.update_smart_tracking_values(ctt, data, interpolation, info, the_x, dt)

        locX = []
        locY = {}

        #prepare dict to store interpolated values
        for locKey, locVal in camtool2.data().interpolation.items():
            locY[locKey] = []

        #interpolate all options
        activeCamKeyframes = data.mode[data.active_mode][data.active_cam].keyframes
        for locVal in activeCamKeyframes:
            locX.append(locVal.keyframe)
            for locKey, locVal2 in locVal.interpolation.items():
                locY[locKey].append(locVal2)

        # if data.is_last_camera() and data.get_n_cameras() > 1:
        #     for i in range(len(locX)):
        #         if locX[i] != None:
        #             if locX[i] > 0.5:
        #                 locX[i] -= 1

            # for locKey, locVal in locY.items():
            #     locX, locY[locKey] = zip(*sorted(zip(locX, locY[locKey])))





        #prepare the_x for last camera
        if data.smart_tracking:
            the_x_tmp = cam.get_st_x()
        else:
            the_x_tmp = the_x

        if data.is_last_camera() and data.get_n_cameras() > 1:
            if the_x > 0.5:
                the_x_tmp -= 1


        #---------------------------------------------------------------
        #LOCATION
        locSplineLen = len(locCameraData.spline["the_x"])
        if locSplineLen > 0:
            locSpline_exists = True
        else:
            locSpline_exists = False


        #spline offset
        locSpline_offset = interpolation.interpolate( the_x_tmp, locX, locY["spline_offset_spline"] )
        if locSpline_offset == None:
            locSpline_offset = locCameraData.spline_offset_spline
        else:
            locCameraData.spline_offset_spline = locSpline_offset

        if data.active_mode == "time":
            locSpline_offset = locSpline_offset * (1000 / replay.get_refresh_rate())

        #spline speed
        locSpline_speed = interpolation.interpolate( the_x_tmp, locX, locY["spline_speed"] )
        if locSpline_speed == None:
            locSpline_speed = locCameraData.spline_speed
        else:
            locCameraData.spline_speed = locSpline_speed

        the_x_tmp_4_spline = the_x_tmp

        if locSpline_exists:
            the_x_tmp_4_spline = (the_x - locCameraData.spline["the_x"][0]) * locSpline_speed - locSpline_offset + locCameraData.spline["the_x"][0]
            if locCameraData.spline["the_x"][locSplineLen - 1] > 1:
                if data.active_mode == "pos":
                    if the_x_tmp_4_spline < 0.5:
                        the_x_tmp_4_spline += 1

        loc_x_spline = None
        loc_y_spline = None
        loc_z_spline = None
        locHeadingSpline = None
        if locSpline_exists:
            #spline_offset relative loc_x
            locHeadingSpline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["rot_z"])
            locSpline_offset_x = vec()
            locValue = interpolation.interpolate( the_x_tmp, locX, locY["spline_offset_loc_x"] )
            if locValue == None:
                locValue = locCameraData.spline_offset_loc_x
            locSpline_offset_x.y = math.cos(locHeadingSpline) * locValue
            locSpline_offset_x.x = math.sin(locHeadingSpline) * locValue

            loc_x_spline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["loc_x"])
            loc_y_spline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["loc_y"])
            loc_z_spline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["loc_z"])
            loc_x_spline += locSpline_offset_x.x
            loc_y_spline += locSpline_offset_x.y

        #transform
        loc_transform_loc_strength = interpolation.interpolate( the_x_tmp, locX, locY["transform_loc_strength"] )
        if loc_transform_loc_strength == None:
            loc_transform_loc_strength = locCameraData.transform_loc_strength
        else:
            locCameraData.transform_rot_strength = loc_transform_loc_strength

        loc_transform_rot_strength = interpolation.interpolate( the_x_tmp, locX, locY["transform_rot_strength"] )
        if loc_transform_rot_strength == None:
            loc_transform_rot_strength = locCameraData.transform_rot_strength
        else:
            locCameraData.transform_rot_strength = loc_transform_rot_strength

        locLoc_x_transform = interpolation.interpolate( the_x_tmp, locX, locY["loc_x"] )
        locLoc_y_transform = interpolation.interpolate( the_x_tmp, locX, locY["loc_y"] )
        locLoc_z_transform = interpolation.interpolate( the_x_tmp, locX, locY["loc_z"] )

        #combining: spline / transform / strength_inv (mouse)
        if loc_x_spline != None or locLoc_x_transform != None:
            if loc_x_spline == None:
                loc_x_spline = ctt.get_position(0)

            if locLoc_x_transform == None:
                locLoc_x_transform = ctt.get_position(0)
            else:
                locLoc_x_transform = locLoc_x_transform * loc_transform_loc_strength + ctt.get_position(0) * (1 - loc_transform_loc_strength)

            if locSpline_exists:
                loc_spline_affect_loc_xy = interpolation.interpolate( the_x_tmp, locX, locY["spline_affect_loc_xy"] )
                if loc_spline_affect_loc_xy == None:
                    loc_spline_affect_loc_xy = locCameraData.spline_affect_loc_xy
                else:
                    locCameraData.spline_affect_loc_xy = loc_spline_affect_loc_xy
            else:
                loc_spline_affect_loc_xy = 0

            ctt.set_position(0, (locLoc_x_transform * (1 - loc_spline_affect_loc_xy) + loc_x_spline * loc_spline_affect_loc_xy) * (1 - strength_inv) + ctt.get_position(0) * strength_inv)


        if loc_y_spline != None or locLoc_y_transform != None:
            if loc_y_spline == None:
                loc_y_spline = ctt.get_position(1)

            if locLoc_y_transform == None:
                locLoc_y_transform = ctt.get_position(1)
            else:
                locLoc_y_transform = locLoc_y_transform * loc_transform_loc_strength + ctt.get_position(0) * (1 - loc_transform_loc_strength)

            if locSpline_exists:
                loc_spline_affect_loc_xy = interpolation.interpolate( the_x_tmp, locX, locY["spline_affect_loc_xy"] )
                if loc_spline_affect_loc_xy == None:
                    loc_spline_affect_loc_xy = locCameraData.spline_affect_loc_xy
                else:
                    locCameraData.spline_affect_loc_xy = loc_spline_affect_loc_xy
            else:
                loc_spline_affect_loc_xy = 0
            ctt.set_position(1, (locLoc_y_transform * (1 - loc_spline_affect_loc_xy) + loc_y_spline * loc_spline_affect_loc_xy) * (1 - strength_inv) + ctt.get_position(1) * strength_inv)


        if loc_z_spline != None or locLoc_z_transform != None:
            if loc_z_spline == None:
                loc_z_spline = ctt.get_position(2)

            if locLoc_z_transform == None:
                locLoc_z_transform = ctt.get_position(2)
            else:
                locLoc_z_transform = locLoc_z_transform * loc_transform_loc_strength + ctt.get_position(0) * (1 - loc_transform_loc_strength)

            if locSpline_exists:
                loc_spline_affect_loc_z = interpolation.interpolate( the_x_tmp, locX, locY["spline_affect_loc_z"] )
                if loc_spline_affect_loc_z == None:
                    loc_spline_affect_loc_z = locCameraData.spline_affect_loc_z
            else:
                loc_spline_affect_loc_z = 0

            locSpline_offset_loc_z = interpolation.interpolate( the_x_tmp, locX, locY["spline_offset_loc_z"] )
            if locSpline_offset_loc_z == None:
                locSpline_offset_loc_z = locCameraData.spline_offset_loc_z
            loc_z_spline += locSpline_offset_loc_z



            ctt.set_position(2, (locLoc_z_transform * (1 - loc_spline_affect_loc_z) + loc_z_spline * loc_spline_affect_loc_z) * (1 - strength_inv) + ctt.get_position(2) * strength_inv)


        #===============================================================
        #ROTATION

        #transform
        locPitch_transform = interpolation.interpolate( the_x_tmp, locX, locY["rot_x"] )
        locRoll_transform = interpolation.interpolate( the_x_tmp, locX, locY["rot_y"] )
        locHeading_transform = interpolation.interpolate( the_x_tmp, locX, locY["rot_z"] )

        #spline
        locPitch_spline = None
        locRoll_spline = None
        #moved up
        #locHeadingSpline = None

        if locSpline_exists:
            locPitch_spline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["rot_x"])
            locRoll_spline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["rot_y"])
            #moved up
            #locHeadingSpline = interpolation.interpolate(the_x_tmp_4_spline, locCameraData.spline["the_x"], locCameraData.spline["rot_z"])


            #offset - rotation
            locSpline_offset_heading = interpolation.interpolate( the_x_tmp, locX, locY["spline_offset_heading"] )
            if locSpline_offset_heading == None:
                locSpline_offset_heading = locCameraData.spline_offset_heading
            locHeadingSpline += locSpline_offset_heading

            locRoll_spline *= math.sin(locSpline_offset_heading + math.pi/2)
            locPitch_spline *= math.sin(locSpline_offset_heading + math.pi/2)

            locSpline_offset_pitch = interpolation.interpolate( the_x_tmp, locX, locY["spline_offset_pitch"] )
            if locSpline_offset_pitch == None:
                locSpline_offset_pitch = locCameraData.spline_offset_pitch
            locPitch_spline += locSpline_offset_pitch


        #---------------------------------------------------------------
        #TRACKING
        #tracking - offset
        locValue = interpolation.interpolate( the_x_tmp, locX, locY["tracking_offset"] )
        if locValue != None:
            locCameraData.tracking_offset = locValue

        if data.smart_tracking:
            locCam_rot_tracking = cam.get_st_cam_rot()

        else:
            loc_cam_rot_to_car_a = cam.calculate_cam_rot_to_tracking_car(ctt, data, info, cam.get_tracked_car(0), dt)

            #tracking - mix
            locCam_rot_tracking = loc_cam_rot_to_car_a
            locValue = interpolation.interpolate( the_x_tmp, locX, locY["tracking_mix"] )
            if locValue == None:
                locValue = locCameraData.tracking_mix
            else:
                locCameraData.tracking_mix = locValue

            if locValue > 0:
                loc_cam_rot_to_car_b = cam.calculate_cam_rot_to_tracking_car(ctt, data, info, cam.get_tracked_car(1), dt)
                loc_cam_rot_to_car_b.z = normalize_angle(loc_cam_rot_to_car_a.z, loc_cam_rot_to_car_b.z)
                locCam_rot_tracking = loc_cam_rot_to_car_a * vec3((1-locValue), (1-locValue), (1-locValue)) + loc_cam_rot_to_car_b * vec3(locValue, locValue, locValue)

        locHeading_4_focus_point = locCam_rot_tracking.z



        #tracking - strength - pitch
        locValue = interpolation.interpolate_sin( the_x_tmp, locX, locY["tracking_strength_pitch"] )
        if locValue != None:
            locCameraData.tracking_strength_pitch = locValue

        #tracking - strength - heading
        locValue = interpolation.interpolate_sin( the_x_tmp, locX, locY["tracking_strength_heading"] )
        if locValue != None:
            locCameraData.tracking_strength_heading = locValue

        loc_tracking_offset_heading = interpolation.interpolate_sin( the_x_tmp, locX, locY["tracking_offset_heading"] )
        if loc_tracking_offset_heading != None:
            locCameraData.tracking_offset_heading = loc_tracking_offset_heading

        loc_tracking_offset_pitch = interpolation.interpolate_sin( the_x_tmp, locX, locY["tracking_offset_pitch"] )
        if loc_tracking_offset_pitch != None:
            locCameraData.tracking_offset_pitch = loc_tracking_offset_pitch


        #---------------------------------------------------------------
        #Combining rotations - heading
        locHeading = ctt.get_heading()
        if locHeading_transform != None or locHeadingSpline != None or data.get_tracking_strength("heading") > 0:

            #prepare values
            if locHeading_transform == None:
                locHeading_transform = locHeading
            else:
                locHeading_transform = locHeading_transform * loc_transform_rot_strength + locHeading * (1 - loc_transform_rot_strength)


            if locHeadingSpline == None:
                locHeadingSpline = locHeading

            if locCam_rot_tracking.z == None:
                locCam_rot_tracking.z = locHeading
            else:
                locCam_rot_tracking.z += locCameraData.tracking_offset_heading


            locHeading_transform = normalize_angle(locHeading, locHeading_transform)
            locCam_rot_tracking.z = normalize_angle(locHeading, locCam_rot_tracking.z)
            locHeadingSpline = normalize_angle(locHeading, locHeadingSpline)

            #prepare strength_invs
            if locSpline_exists:
                locStrength_spline = camtool2.get_data("spline_affect_heading", True, False)
            else:
                locStrength_spline = 0

            loc_strength_tracking = data.get_tracking_strength("heading")

            locHeading =  (
                                (
                                    (locHeading_transform * (1 - loc_strength_tracking) + locCam_rot_tracking.z * loc_strength_tracking)
                                    * (1 - locStrength_spline) + locHeadingSpline * locStrength_spline
                                )
                                * (1 - strength_inv) + locHeading * strength_inv

                            )
        #---------------------------------------------------------------
        #Combining rotations - pitch
        locPitch = ctt.get_pitch()
        if locPitch_transform != None or locPitch_spline != None or data.get_tracking_strength("pitch") > 0:

            #prepare values
            if locPitch_transform == None:
                locPitch_transform = locPitch
            else:
                locPitch_transform = locPitch_transform * loc_transform_rot_strength + locPitch * (1 - loc_transform_rot_strength)

            if locPitch_spline == None:
                locPitch_spline = locPitch

            if locCam_rot_tracking.x == None:
                locCam_rot_tracking.x = locPitch
            else:
                locCam_rot_tracking.x += locCameraData.tracking_offset_pitch

            #prepare strength_invs
            if locSpline_exists:
                locStrength_spline = camtool2.get_data("spline_affect_pitch", True, False)
            else:
                locStrength_spline = 0

            loc_strength_tracking = data.get_tracking_strength("pitch")


            locPitch =    (
                                (
                                    (locPitch_transform * (1 - loc_strength_tracking) + locCam_rot_tracking.x * loc_strength_tracking)
                                    * (1 - locStrength_spline) + locPitch_spline * locStrength_spline
                                )
                                * (1 - strength_inv) + locPitch * strength_inv
                            )

        #---------------------------------------------------------------
        #Combining rotations - roll
        locRoll = ctt.get_roll()
        if locRoll_transform != None or locRoll_spline != None:

            #prepare values
            if locRoll_transform == None:
                locRoll_transform = locRoll
            else:
                locRoll_transform = locRoll_transform# * loc_transform_rot_strength + locRoll * (1 - loc_transform_rot_strength)

            if locRoll_spline == None:
                locRoll_spline = locRoll

            #prepare strength_invs
            if locSpline_exists:
                locStrength_spline = camtool2.get_data("spline_affect_roll", True, False)
            else:
                locStrength_spline = 0

            locRoll =  (locRoll_transform * (1 - locStrength_spline) + locRoll_spline * locStrength_spline) * (1 - strength_inv) + locRoll * strength_inv

        #---------------------------------------------------------------

        locCamera_shake_strength = interpolation.interpolate_sin( the_x_tmp, locX, locY["camera_shake_strength"] )
        if locCamera_shake_strength != None:
            locCameraData.camera_shake_strength = locCamera_shake_strength


        locShake_factor = 0.75 * data.get_tracking_strength("heading") + 0.01 * (1 - min(1, data.get_tracking_strength("heading") + loc_transform_rot_strength) )
        locShake = cam.get_shake(data, info.graphics.replayTimeMultiplier) * vec3(1 - strength_inv * locShake_factor, 0, 1 - strength_inv * locShake_factor)
        ctt.set_rotation(locPitch + locShake.x, locRoll, locHeading + locShake.z)


        #===============================================================
        #CAMERA
        #fov
        loc_strength_tracking_heading = data.get_tracking_strength("heading")

        locFov = interpolation.interpolate_sin( the_x_tmp, locX, locY["camera_fov"] )
        if locFov != None:
            locFov =  ctt.convert_fov_2_focal_length(locFov, True)
        else:
            locFov = ctt.get_fov()

        if data.smart_tracking:
            if data.has_camera_changed():
                cam.reset_smart_tracking()
            locSt_fov = cam.get_st_fov()
            locSt_fov_mix = cam.get_st_fov_mix()
            locSt_fov = locSt_fov * loc_strength_tracking_heading + locFov * (1 - loc_strength_tracking_heading)
            locFov = locFov * (1 - locSt_fov_mix) + locSt_fov * locSt_fov_mix
        ctt.set_fov(locFov * (1 - strength_inv) + ctt.get_fov() * strength_inv )



        #---------------------------------------------------------------
        #focus point
        locCamera_use_tracking_point = locCameraData.camera_use_tracking_point

        locFocus_point = interpolation.interpolate( the_x_tmp, locX, locY["camera_focus_point"] )
        if locFocus_point == None:
            locFocus_point = ctt.get_focus_point()

        locMix = interpolation.interpolate( the_x_tmp, locX, locY["tracking_mix"] )
        if locMix == None:
            locMix = locCameraData.tracking_mix

        if locHeading_4_focus_point != None:
            locHeading_4_focus_point = normalize_angle(ctt.get_heading(), locHeading_4_focus_point)
        else:
            locHeading_4_focus_point = ctt.get_heading()

        locFocus_point = cam.calculate_focus_point(ctt, locMix, locHeading_4_focus_point, dt) * locCamera_use_tracking_point + locFocus_point * (1 - locCamera_use_tracking_point)
        locFocus_point = locFocus_point * (1 - strength_inv) + 300 * strength_inv
        ctt.set_focus_point( locFocus_point )