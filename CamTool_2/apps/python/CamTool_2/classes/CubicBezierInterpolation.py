import math
try:
    from classes.general import *
except:
    try:
        from general import *
    except:
        pass


class CubicBezierInterpolation(object):
    def __init__(self):
        self.spline_index = 0

    def interpolate_sin(self, time, x, y):
        try:
            if len(y) == 0:
                return None

            self.points = self.__sanitize(x, y)

            if len(self.points) == 0:
                return None

            if len(self.points) == 1:
                return self.points[0].y

            self.control_points = cca.controlPointsFromPoints(self.points)

            self.active_index = None
            for self.i in range(len(self.points)):
                if time < self.points[len(self.points)-1].x:
                    if time > self.points[self.i].x:
                        self.active_index = self.i

                else:
                    return self.points[len(self.points)-1].y


            if self.active_index == None:
                return self.points[0].y



            self.t = time - self.points[self.active_index].x
            self.tx = self.points[self.active_index + 1].x - self.points[self.active_index].x

            if self.tx != 0:
                self.ratio = math.sin( (self.t / self.tx) * math.pi - math.pi/2  ) * 0.5 + 0.5
            else:
                self.ratio = 1

            self.ratio = min(1, max(0, self.ratio))
            return self.points[self.active_index].y * (1 - self.ratio) + self.points[self.active_index + 1].y * self.ratio


        except Exception as e:
            debug(e)

    def interpolate_spline(self, time, x, y, cyclic = False):
        try:
            self.n_elements = len(y)

            if self.n_elements == 0:
                return None

            if self.n_elements == 1:
                return y[0]

            if x[0] >= time:
                if cyclic:
                    self.t = time - x[self.n_elements-1] + 1
                    self.tx = x[0] - x[self.n_elements-1] + 1
                    if self.tx != 0:
                        self.ratio = self.t / self.tx
                    else:
                        self.ratio = 1
                    return y[self.n_elements-1] * (1 - self.ratio) + y[0] * self.ratio
                else:
                    return y[0]

            if x[self.n_elements-1] <= time:
                if cyclic:
                    self.t = time - x[self.n_elements-1]
                    self.tx = x[0] + 1 - x[self.n_elements-1]
                    if self.tx != 0:
                        self.ratio = self.t / self.tx
                    else:
                        self.ratio = 1
                    return y[self.n_elements-1] * (1 - self.ratio) + y[0] * self.ratio
                else:
                    return y[self.n_elements-1]

            for self.i in range(self.n_elements):
                if x[self.i] >= time:
                    if self.i == 0:
                        return y[0]
                    else:
                        self.spline_index = self.i - 1
                        break



            self.t = time - x[self.spline_index]
            self.tx = x[self.spline_index + 1] - x[self.spline_index]

            if self.tx != 0:
                self.ratio = self.t / self.tx
            else:
                self.ratio = 1

            return y[self.spline_index] * (1 - self.ratio) + y[self.spline_index + 1] * self.ratio




        except Exception as e:
            debug(e)

    def interpolate(self, time, x, y):
        try:
            if len(y) == 0:
                self.spline_index = None
                return None

            self.points = self.__sanitize(x, y)

            if len(self.points) == 0:
                self.spline_index = 0
                return None

            if len(self.points) == 1:
                self.spline_index = 0
                return self.points[0].y

            self.control_points = cca.controlPointsFromPoints(self.points)

            self.active_index = None
            for self.i in range(len(self.points)-1):
                if time < self.points[len(self.points)-1].x:
                    if time > self.points[self.i].x:
                        self.active_index = self.i
                else:
                    return self.points[len(self.points)-1].y

            self.spline_index = self.active_index
            if self.active_index == None:
                self.spline_index = 0
                return self.points[0].y




            self.x = [ self.points[self.active_index].x, self.control_points[self.active_index].controlPoint1.x, self.control_points[self.active_index].controlPoint2.x, self.points[self.active_index+1].x ]
            self.y = [ self.points[self.active_index].y, self.control_points[self.active_index].controlPoint1.y, self.control_points[self.active_index].controlPoint2.y, self.points[self.active_index+1].y ]

            if __name__ == "__main__":
                print("Time: {0}".format(time))
                for self.i in range(4):
                    print("{2} -> x:{0:.2f}\t y:{1:.2f}".format(self.x[self.i], self.y[self.i], self.i) )

            if len(self.points) == 2:
                self.multiplier = 2
            else:
                self.multiplier = 1

            if self.active_index == 0:
                self.smooth = (time - self.points[0].x) / (self.points[1].x - self.points[0].x)
                if self.smooth < (1 / self.multiplier):
                    self.smooth = math.sin( math.radians(min( self.smooth * self.multiplier, 1) * 90) )
                    return (self.GetY(time, self.x, self.y) * self.smooth) + (self.points[0].y * (1-self.smooth))

            if self.active_index == len(self.points)-2:
                self.duration = (self.points[len(self.points)-1].x - self.points[len(self.points)-2].x)
                self.smooth = 1-(max((time - self.points[len(self.points)-2].x - (self.duration/2)) / self.duration, 0) * self.multiplier)
                self.smooth = math.sin(math.radians(self.smooth * 90))
                return (self.GetY(time, self.x, self.y) * self.smooth) + (self.points[len(self.points)-1].y * (1-self.smooth))

            return self.GetY(time, self.x, self.y)
        except Exception as e:
            debug(e)

    def __sanitize(self, x, y):
        try:
            self.result = []

            for self.i in range(len(y)):
                if x[self.i] != None and y[self.i] != None:
                    self.result.append( vec(x[self.i],y[self.i]) )

            return self.result

        except Exception as e:
            debug(e)

    def get_last_active_index(self):
        return self.spline_index

    #Bezier cubic - code from stackoverflow. It gives better results, but I don't how to implement it, if there is more than 4 keyframes.
    def GetY(self, time, x, y):
        try:
            #Determine t
            if time == x[0]:
                # Handle corner cases explicitly to prevent rounding errors
                self.t = 0
            elif time == x[3]:
                self.t = 1
            else:
                # Calculate t
                self.a = -x[0] + 3 * x[1] - 3 * x[2] + x[3]
                self.b = 3 * x[0] - 6 * x[1] + 3 * x[2]
                self.c = -3 * x[0] + 3 * x[1]
                self.d = x[0] - time
                self.tTemp = self.SolveCubic(self.a, self.b, self.c, self.d)
                if self.tTemp == None:
                    return None
                self.t = self.tTemp

            # Calculate y from t
            return self.Cubed(1 - self.t) * y[0] \
                + 3 * self.t * self.Squared(1 - self.t) * y[1] \
                + 3 * self.Squared(self.t) * (1 - self.t) * y[2] \
                + self.Cubed(self.t) * y[3]

        except Exception as e:
            debug(e)



    # Solves the equation ax³+bx²+cx+d = 0 for x ϵ ℝ
    # and returns the first result in [0, 1] or null.
    def SolveCubic(self, a,b,c,d):
        if a == 0:
            return self.SolveQuadratic(b, c, d)
        if d == 0:
            return 0

        b /= a
        c /= a
        d /= a

        self.q = (3.0 * c - self.Squared(b)) / 9.0
        self.r = (-27.0 * d + b * (9.0 * c - 2.0 * self.Squared(b))) / 54.0
        self.disc = self.Cubed(self.q) + self.Squared(self.r)
        self.term1 = b / 3.0

        if self.disc > 0:
            self.s = self.r + (self.disc**0.5)

            if self.s < 0:
                self.s = (-1) * self.CubicRoot( (-1)*self.s )
            else:
                self.s = self.CubicRoot( self.s )

            self.t = self.r - (self.disc**0.5)
            if self.t < 0:
                self.t = (-1) * self.CubicRoot( (-1)*self.t )
            else:
                self.t = self.CubicRoot( self.t )

            self.result = (-1) * self.term1 + self.s + self.t

            if self.result >= 0 and self.result <= 1:
                return self.result

        elif self.disc == 0:
            if self.r < 0:
                self.r13 = (-1) * self.CubicRoot( (-1)*self.r )
            else:
                self.r13 = self.CubicRoot( self.r )

            self.result = (-1) * self.term1 + 2.0 * self.r13
            if self.result >= 0 and self.result <= 1:
                return result

            self.result = (-1)*(self.r13 + self.term1)
            if self.result >= 0 and self.result <= 1:
                return self.result
        else:
            self.q = (-1)*self.q
            self.dum1 = self.q * self.q * self.q
            self.dum1 = math.acos(self.r / (self.dum1**0.5) )
            self.r13 = 2.0 * (self.q**0.5)

            self.result = (-1)*self.term1 + self.r13 * math.cos(self.dum1 / 3.0)
            if self.result >= 0 and self.result <= 1:
                return self.result

            self.result = (-1)*self.term1 + self.r13 * math.cos((self.dum1 + 2.0 * math.pi) / 3.0)
            if self.result >= 0 and self.result <= 1:
                return self.result

            self.result = (-1)*self.term1 + self.r13 * math.cos((self.dum1 + 4.0 * math.pi) / 3.0)
            if self.result >= 0 and self.result <= 1:
                return self.result

        return None


    # Solves the equation ax² + bx + c = 0 for x ϵ ℝ
    # and returns the first result in [0, 1] or null.
    def SolveQuadratic(self, a, b, c):
        if a == 0:
            if b == 0:
                return c
            else:
                return -c/b

        self.result = ((-1)*b + ((self.Squared(b) - 4 * a * c)**0.5)) / (2 * a)
        if self.result >= 0 and self.result <= 1:
            return self.result

        self.result = ((-1)*b - ((self.Squared(b) - 4 * a * c)**0.5)) / (2 * a)
        if self.result >= 0 and self.result <= 1:
            return self.result

        return None


    def Squared(self, f):
        return f * f

    def Cubed(self, f):
        return f * f * f

    def CubicRoot(self, f):
        return f**(1/3)



class CubicCurveAlgorithm(object):
    def __init__(self):
        self.firstControlPoints = []
        self.secondControlPoints = []

    def controlPointsFromPoints(self, dataPoints):
        self.firstControlPoints = []
        self.secondControlPoints = []

        #Number of Segments
        self.count = len(dataPoints) - 1

        #P0, P1, P2, P3 are the points for each segment, where P0 & P3 are the knots and P1, P2 are the control points.
        if self.count == 1:
            self.P0 = dataPoints[0]
            self.P3 = dataPoints[1]

            #Calculate First Control Point
            #3P1 = 2P0 + P3

            self.P1x = (2*self.P0.x + self.P3.x)/3
            self.P1y = (2*self.P0.y + self.P3.y)/3

            self.firstControlPoints.append(vec(self.P1x, self.P1y))

            #Calculate second Control Point
            #P2 = 2P1 - P0
            self.P2x = (2*self.P1x - self.P0.x)
            self.P2y = (2*self.P1y - self.P0.y)

            self.secondControlPoints.append(vec(self.P2x, self.P2y))
        else:
            self.firstControlPoints = {"count": self.count, "repeatedValue": None}

            self.rhsArray = []

            #Array of Coefficients
            self.a = []
            self.b = []
            self.c = []

            for self.i in range(self.count):

                self.rhsValueX = 0.0
                self.rhsValueY = 0.0

                self.P0 = dataPoints[self.i];
                self.P3 = dataPoints[self.i+1];

                if self.i == 0:
                    self.a.append(0)
                    self.b.append(2)
                    self.c.append(1)

                    #rhs for first segment
                    self.rhsValueX = self.P0.x + 2*self.P3.x
                    self.rhsValueY = self.P0.y + 2*self.P3.y

                elif self.i == self.count-1:
                    self.a.append(2)
                    self.b.append(7)
                    self.c.append(0)

                    #rhs for last segment
                    self.rhsValueX = 8*self.P0.x + self.P3.x
                    self.rhsValueY = 8*self.P0.y + self.P3.y
                else:
                    self.a.append(1)
                    self.b.append(4)
                    self.c.append(1)

                    self.rhsValueX = 4*self.P0.x + 2*self.P3.x
                    self.rhsValueY = 4*self.P0.y + 2*self.P3.y

                self.rhsArray.append(vec(self.rhsValueX, self.rhsValueY))

            #Solve Ax=B. Use Tridiagonal matrix algorithm a.k.a Thomas Algorithm

            for self.i in range(1, self.count):
                self.rhsValueX = self.rhsArray[self.i].x
                self.rhsValueY = self.rhsArray[self.i].y

                self.prevRhsValueX = self.rhsArray[self.i-1].x
                self.prevRhsValueY = self.rhsArray[self.i-1].y

                self.m = self.a[self.i]/self.b[self.i-1]

                self.b1 = self.b[self.i] - self.m * self.c[self.i-1];
                self.b[self.i] = self.b1

                self.r2x = self.rhsValueX - self.m * self.prevRhsValueX
                self.r2y = self.rhsValueY - self.m * self.prevRhsValueY

                self.rhsArray[self.i] = vec(self.r2x, self.r2y)


            #Get First Control Points

            #Last control Point
            self.lastControlPointX = self.rhsArray[self.count-1].x/self.b[self.count-1]
            #self.lastControlPointY = dataPoints[self.count].y
            self.lastControlPointY = self.rhsArray[self.count-1].y/self.b[self.count-1]

            self.firstControlPoints[self.count-1] = vec(self.lastControlPointX, self.lastControlPointY)

            for self.i in range(self.count-2, -1, -1):
                try:
                    self.nextControlPoint = self.firstControlPoints[self.i+1]
                    self.controlPointX = (self.rhsArray[self.i].x - self.c[self.i] * self.nextControlPoint.x)/self.b[self.i]
                    self.controlPointY = (self.rhsArray[self.i].y - self.c[self.i] * self.nextControlPoint.y)/self.b[self.i]

                    if self.i == 0:
                        self.firstControlPoints[self.i] = vec(self.controlPointX, dataPoints[0].y)
                    else:
                        self.firstControlPoints[self.i] = vec(self.controlPointX, self.controlPointY)
                    #self.firstControlPoints[self.i] = vec(self.controlPointX, self.controlPointY)
                except:
                    continue



            #Compute second Control Points from first

            for self.i in range(self.count):

                if self.i == self.count-1:
                    self.P3 = dataPoints[self.i+1]

                    try:
                        self.P1 = self.firstControlPoints[self.i]
                    except:
                        continue

                    self.controlPointX = (self.P3.x + self.P1.x)/2
                    self.controlPointY = dataPoints[self.count].y
                    #self.controlPointY = (self.P3.y + self.P1.y)/2


                    self.secondControlPoints.append(vec(self.controlPointX, self.controlPointY))

                else:
                    self.P3 = dataPoints[self.i+1]

                    try:
                        self.nextP1 = self.firstControlPoints[self.i+1]
                    except:
                        continue

                    self.controlPointX = 2*self.P3.x - self.nextP1.x
                    self.controlPointY = 2*self.P3.y - self.nextP1.y

                    self.secondControlPoints.append(vec(self.controlPointX, self.controlPointY))


        self.controlPoints = []

        for self.i in range(self.count):
            try:
                self.firstControlPoint = self.firstControlPoints[self.i],
                self.secondControlPoint = self.secondControlPoints[self.i]
                self.segment = self.CubicCurveSegment(self.firstControlPoint[0], self.secondControlPoint)
                self.controlPoints.append(self.segment)
            except:
                continue

        return self.controlPoints

    class CubicCurveSegment(object):
        def __init__(self, controlPoint1, controlPoint2):
            self.controlPoint1 = controlPoint1
            self.controlPoint2 = controlPoint2

cca = CubicCurveAlgorithm()
interpolation = CubicBezierInterpolation()




if __name__ == "__main__":
    x = 2203
    fov = 50
    f = 2 * math.atan(x / (2 * fov)) * 180 / math.pi
    print( f )
    print( x / (2 * math.tan(math.pi * f / 360)) )
    # x = [1,2,3,4]
    # y = [4,3,2,1]
    # print("Interpolate:")
    # print(interpolation.interpolate_linear(3.1, x,y))
