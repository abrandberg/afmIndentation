### Packages used
using Statistics
using NaNStatistics
using Optim
using DelimitedFiles


### Structs used
struct hyperParameters
    sampleRate              ::Int64          # [Hz] Sample rate.
    unloadingFitRange       ::Int64          # [-] Vector samples lengths (measured from start of unloading) to be included in unload fit.
    unloadingFitFunction    ::String         # [string] Function to use when fitting.
    compensateCreep         ::Bool           # [Bool] Compensate creep using Feng's method, y/n
    constrainHead           ::Int            # Experimental, not implemented
    constrainTail           ::Int            # Experimental, not implemented
    machineCompliance       ::Float64        # Machine compliance
end

struct control
    plotMode                ::Bool           # Activates plotting of intermediate results
    verboseMode             ::Bool           # Verbose output
end

struct metaInfoExperimentalSeries
    designatedName          ::String         # Designated name
    relativeHumidity        ::Float64        # Relative humidity
    indenterType            ::String
    indentationNormal       ::String
    springConstant          ::Float64
    areaFile                ::String
    targetDir               ::String
    thermalHoldTime         ::Int64          # Should be changed to something of unit "second".
end




"""
ReadIBW(filename) 

Reads a .IBW binary file, extracting the position and force signal of the AFM indenter. 

filename is the string to a file which either needs to be absolute or on the path.
"""
function readIBW(filename)

    A = open( filename, "r")   
    firstByte = read(A, Int8)
    close(A)
    
    if firstByte == 0
        machineFormat = 'b'
    else
        machineFormat = 'l'
    end
    
    A = open( filename, "r")
    version         = read(A, Int16)  
    checksum        = ltoh(read(A,UInt16)) # Does not work           
    wfmSize         = ltoh(read(A, Int32))
    formulaSize     = ltoh(read(A, Int32))
    noteSize        = ltoh(read(A, Int32)) # Does not work
    dataEUnitsSize  = ltoh(read(A, Int32))
    dimEUnitsSize   = Array{Int32, 1}(undef, 4); read!(ltoh(A),dimEUnitsSize)
    dimLabelsSize   = Array{Int32, 1}(undef, 4); read!(ltoh(A),dimLabelsSize)
    sIndicesSize    = read(A, Int32)
    optionSize1     = read(A, Int32)
    optionSize2     = read(A, Int32)   
    ignore          = read(A, Int32)
    CreationDate    = read(A, UInt32)
    modData         = read(A, UInt32)
    npnts           = read(A, Int32)                  # WORKS!
    
    type = read(A, Int16)
    if type == 2
        datatype = "single"
    elseif type == 4
        datatype = "double"
    else
        println("ERROR")
    end

    read(A, Int16)
    for aLoop = 1:6
        read(A, Char)
    end
    read(A, Int16)

    for aLoop = 1:32
        read(A, Char)
    end
    for aLoop = 1:6
        read(A, Int32)
    end

    sfA = Array{Float64, 1}(undef, 4)
    read!(A, sfA)
    sfB = Array{Float64, 1}(undef, 4)
    read!(A, sfB)

    dUnits = Array{Char, 1}(undef,4)
    for aLoop = 1:4
        dUnits[aLoop] = read(A, Char)
    end
    dUnits = join(dUnits)

    xUnits  = Array{Char, 1}(undef, 16)
    for aLoop = 1:16
        xUnits[aLoop] = read(A, Char)
    end
    xUnits = join(xUnits)

    fsValid = read(A, Int16)
    whpad3 = read(A, Int16)
    read(A, Float64)
    read(A, Float64)
    for aLoop = 1:26
        read(A, Int32)
    end
    for aLoop = 1:3
        read(A, Int16)
    end
    read(A, Char)
    read(A, Char)
    read(A, Int32)
    read(A, Int16)
    read(A, Int16)
    read(A, Int32)
    modDate = read(A, Int32)
    creationDate = read(A, Int32)
    wdata = Array{Float32, 1}(undef, npnts); read!(A,wdata)

    close(A)

    x0 = Float64(sfB[1]*fsValid)
    dx = Float64(sfA[1]*fsValid)
    return wdata#, npnts# , dUnits, x0, dx, xUnits

end



#data, dUnits, x0, dx, xUnits = ReadIBW(filename)
"""
IBWtoTXT(filename)

Takes a filename, calls ReadIBW and formats the returned data into x and y signals where
x is the position of the sensor and y is the deflection of the sensor.
"""
function IBWtoTXT(filename::String)
    data = readIBW(filename)
    lengthOfData = length(data) ÷ 3

    #t = data[1:lengthOfData]
    y = data[lengthOfData+1:2*lengthOfData]
    x = data[2*lengthOfData+1:3*lengthOfData]
    return [x y]
end

function dataPreProcessing(filename::String)
    xy0 = IBWtoTXT(filename)
    # Import signal
    xy0 .*= 1e9     
    # Convert to nano-meters

    return xy0
end



function offsetAndDriftCompensation(xy::Matrix{Float32})
    endRangeBaseFit = 25;
    breakForContact = true;
    aLoop = 0;
    basefit = 0

    while breakForContact
        aLoop += 1

        sIdx = min(10+endRangeBaseFit*(aLoop-1), size(xy,1)-endRangeBaseFit);
        eIdx = min(10+endRangeBaseFit*(aLoop), size(xy,1)-1);

        dPdt = 100*(xy[eIdx,2] - xy[sIdx,2]) / endRangeBaseFit;

        if dPdt > 3.3  && aLoop > 3
            basefit = endRangeBaseFit*(aLoop-1);
            breakForContact = false;
            #println("if")
        elseif endRangeBaseFit*aLoop > 1000
            basefit = endRangeBaseFit*7;
            breakForContact = false;
            #println("elseif")
        end
    end
   
    zeroLineM = ones(length(xy[10:basefit,1])) \ xy[10:basefit,2]
    xy[:,2] .-= zeroLineM

    # Locate the point where the ramp begins.
    noise = max(0.1, std(xy[10:basefit,2]) );
    rampStartIdx = max(1, findfirst(x -> x > 4.0*noise, xy[:,2]) - 1);
    xZero = xy[rampStartIdx,1];
    xy[:,1] .-= xZero;                                       # Shift the curve by the value at the start of the ramp.
    xy[:,2] .-= xy[rampStartIdx,2];
    
    zeroLineD = xy[10:basefit,1] \ xy[10:basefit,2];

    zeroLine = [zeroLineD zeroLineM];

    return xy , basefit , zeroLine , rampStartIdx, xZero   
end



function subdirImport(placeToLook::String,stringToMatch::String)
    return filter(x-> contains(x, stringToMatch) , readdir(placeToLook))
end

function findStartOfHold(xy::Matrix{Float32}, directionOfSearch::String)
    # 1. Determine range of deflection values.
    # 2. Bin the values (heuristic bin size at the moment)
    # 3. Determine the most common deflection value at the highest load levels under the assumption that this bin will contain 
    #    the hold sequence.
    # 4. Determine the mean value of all values larger than this bin value.
    # 5. Find the first time the vector exceeds this value.
    # 6. This is taken as the first value in the hold sequence.

    sensorRange = maximum(xy[:,2]) - minimum(xy[:,2])
    vecLengthTemp = Int64(round(4.0*sensorRange))
    edgesOfHist = range(minimum(xy[:,2]), maximum(xy[:,2]), length = vecLengthTemp)
    histTemp = histcounts(xy[:,2] , edgesOfHist)
    
    tailVecStart = Int64(round(0.9*vecLengthTemp))

    peakIdx = argmax(histTemp[tailVecStart:end])
    peakIdx += tailVecStart-1
    
    idxTemp = map(x -> x > edgesOfHist[peakIdx], xy[:,2])
    
    meanOfPlateau = mean(xy[idxTemp,2])

    if cmp(directionOfSearch,"first") == 0
        returnIdx = findfirst(x -> x ≥ meanOfPlateau, xy[:,2])
    elseif cmp(directionOfSearch,"last") == 0
        returnIdx = findlast(x -> x ≥ meanOfPlateau, xy[:,2])
    end

    return returnIdx

end


function determineThermalCreep(xy::Matrix{Float32},sampleRate::Int64,thermalHoldTime::Int64,ctrl::control)
    sensorRange = maximum(xy[:,2]) - minimum(xy[:,2])
    vecLengthTemp = Int64(round(0.1*sensorRange));
    edgesOfHist = range(minimum(xy[:,2]), maximum(xy[:,2]), length = vecLengthTemp)
    peakIdx = argmax(histcounts(xy[:,2] , edgesOfHist))
    
    idxTemp = (xy[:,2] .< edgesOfHist[peakIdx+1]) .& (xy[:,2] .> edgesOfHist[max(1,peakIdx-1)])
    meanOfPlateau = mean(xy[idxTemp,2])
    stdOfPlateau = std(xy[idxTemp,2])
    
    noiseMultiplier = 5.0; # 15 # OBS HARD CODED AND SHOULD BE PULLED OUT!
    thermalHoldStartIdx = findlast(x -> x > meanOfPlateau+noiseMultiplier*stdOfPlateau, xy[:,2])
    thermalHoldEndIdx = findlast(x -> x > meanOfPlateau-noiseMultiplier*stdOfPlateau, xy[:,2])

    thermalHoldStartIdx += sampleRate
    thermalHoldEndIdx -= sampleRate
    
    # Ensure that the thermal hold sequence contains at least 25 seconds (out of the 30 secounds
    # specified).
    if thermalHoldStartIdx > thermalHoldEndIdx
        ctrl.verboseMode && println("Missed thermal hold. Increasing search range.")
        
        while thermalHoldTime+thermalHoldStartIdx > thermalHoldEndIdx
            noiseMultiplier += 1.0
            thermalHoldStartIdx = findlast(x -> x > meanOfPlateau+noiseMultiplier*stdOfPlateau, xy[:,2])
            thermalHoldEndIdx = findlast(x -> x > meanOfPlateau-noiseMultiplier*stdOfPlateau, xy[:,2])

            try
            thermalHoldStartIdx += sampleRate
            thermalHoldEndIdx -= sampleRate
            catch
                return 0.0
                println("Failure in the termal hold calculation")
            end
        end
        ctrl.verboseMode && println("Thermal hold found using multiplier $noiseMultiplier")
    end 
    
    # Fit a function of displacement (due to thermal fluctuation)
    # h_thermal(time) = A1 + A2*time^A3 
    thermalHoldDisplacement = xy[thermalHoldStartIdx:thermalHoldEndIdx,1];
    thermalHoldTime = collect(1:length(thermalHoldDisplacement))./sampleRate;
    
    deltaDisp = (xy[thermalHoldEndIdx,1] - xy[thermalHoldStartIdx,1])

    thermalCreepFun(x) = xy[thermalHoldStartIdx,1] .+ x[1].*(thermalHoldTime)#.^x[2]
    thermalHoldMinFun(x) = sqrt(sum((   (thermalCreepFun(x) .- thermalHoldDisplacement)./thermalHoldDisplacement ).^2))
    result = optimize(thermalHoldMinFun, [deltaDisp], BFGS())
    thermal_p = result.minimizer

    
    # Estimate the thermal drift rate by taking the median of the differentiated h_thermal
    # dhtdt = d(h_thermal(time))/d(time)
    # The functional form accounts for any viscous effects lingering from the unloading at the start
    # of the thermal hold, while the median provides a roboust average of the thermal drift rate.
    #dhtdt = median(thermal_p[1] .* thermal_p[2].*thermalHoldTime.^(thermal_p[2] - 1));
    dhtdt = thermal_p[1];
end


function determineCreepDuringHold(xy_hold,sampleRate::Int64)
    # Fit the creep during the hold time at maximum load to a linear spring-dashpot model
    #
    # Equation (17c) - not labeled in [1]
    # 
    # h(t) = h_i + \beta * t.^(1/3)
    #
    #   h(t)    - Displacement as a function of time during hold sequence.
    #   h_i     - Fitting constant
    #   \beta   - Fitting constant
    #   t       - Time

    holdTimeVals = collect(1:length(xy_hold[:,1])) ./ sampleRate
    # Generate time signal

    deltaDisp = (xy_hold[end,1] - xy_hold[1,1])

    # Define fitting functions
    hOftFun(x) = xy_hold[1,1] .+ x[1].*holdTimeVals.^x[2]
    minFcn(x) = sqrt( sum( ( (hOftFun(x) - xy_hold[:,1])./ xy_hold[:,1] ).^2 ) )
    holdDrift = optimize(minFcn, [deltaDisp 0.33], BFGS())
    crp_p = holdDrift.minimizer

    h_dot_tot = crp_p[1] * crp_p[2]*holdTimeVals[end]^(crp_p[2] - 1.0)

    return max(h_dot_tot, 0.0)
end


function modulusfitter(indentationSet::metaInfoExperimentalSeries,hyperParameters,ctrl::control,resultFile::String)
    xy = dataPreProcessing(indentationSet.targetDir*resultFile)
    # Load raw displacements

    #ctrl.plotMode && display(plot([xy[1:100:end,1]],[xy[1:100:end,2]]))

    xy , basefit , zeroLine , rampStartIdx, xZero  = offsetAndDriftCompensation(xy)
    # Find initial contact
    #ctrl.plotMode && display(plot!(xy[1:100:end,1],xy[1:100:end,2]))

    xy[:,1] .-= xy[:,2]
    xy[:,2] .*= indentationSet.springConstant
    xy[:,1] .-= hyperParameters.machineCompliance.*xy[:,2];
    # Convert displacement-deflection matrix to indentation-force matrix
        
    #################################################################
    # Determine the start of the hold time at circa max force.
    # 
    # 1. Determine range of deflection values.
    # 2. Bin the values (heuristic bin size at the moment)
    # 3. Determine the most common deflection value at the highest load levels under the assumption that this bin will contain 
    #    the hold sequence.
    # 4. Determine the mean value of all values larger than this bin value.
    # 5. Find the first time the vector exceeds this value.
    # 6. This is taken as the first value in the hold sequence.
    holdStartIdx = findStartOfHold(xy,"first")
    ctrl.plotMode && display(plot(xy[:,1], xy[:,2], xlims = (0.0, maximum(xy[:,1])), xlab = "Indentation [nm]", ylab = "Force [uN]", legend = false))
    # ctrl.plotMode && display(plot!([xy[holdStartIdx,1]], [xy[holdStartIdx,2]], 
    #                          seriestype = :scatter, lab = "Start of hold", legend = :topleft))

    # Split into loading and unloading.
    #xy_load = xy[1:holdStartIdx,:];
    xy_unld1 = xy[holdStartIdx:end,:];

    #Determine the end of the hold time.
    unloadStartIdx = findStartOfHold(xy_unld1,"last")
    #ctrl.plotMode && display(plot!([xy_unld1[unloadStartIdx,1]], [xy_unld1[unloadStartIdx,2]],seriestype = :scatter))

    # Split into two new pieces
    xy_hold = xy_unld1[1:unloadStartIdx-1,:];
    xy_unld = xy_unld1[unloadStartIdx:end,:];

    # Accept only indentations that had positive creep. "Negative" creep (indenter moves outwards 
    # during hold sequence) can occur if the thermal drift is substantial, but this typically
    # indicates that the system was not in equilibrium (since the thermal drift dominates the creep)
    # and furthermore it messes up the mathematical framework if you accept such indentations (see
    # Cheng & Cheng articles.)
    condition1 = xy[holdStartIdx,1] < xy_unld1[unloadStartIdx,1] 
    
    # Accept only monotonously increasing load-displacement curves. A curve may show weird behaviour
    # and our solution is to simply drop the curve in that case. 
    condition2 = minimum(xy[rampStartIdx:holdStartIdx,1]) > (0.0-eps())
    condition3 = maximum(xy_unld[:,1]) < (xy_unld[1,1]+0.5)


    ctrl.plotMode && display(title!(string(condition3)))
    sleep(1.0)
    
    if condition1 && condition2 && condition3
        xy_unld5 = xy_unld[1:Int64(round(2000*0.95)),:];  # OBS 2000 is hard coded!
        # Make sure that the thermal hold sequence is not included in the unloading curve.

        dhtdt = determineThermalCreep(xy,hyperParameters.sampleRate,indentationSet.thermalHoldTime,ctrl)
        #dhtdt == 0.0 && return 0.0
   
        # Fitting of the unloading curve.
        stiffness_fit = Array{Float64}(undef,1)    
        dispVals = xy_unld5[1:hyperParameters.unloadingFitRange,1]
        forceVals = xy_unld5[1:hyperParameters.unloadingFitRange,2]
        Fmax = xy_unld5[1,2]               # Maximum force during unloading

        if cmp(hyperParameters.unloadingFitFunction,"Oliver-Pharr") == 0
            Dmax = xy_unld5[1,1]               
            # Maximum indentation depth during unloading
            
            function unloadFitFun(fitCoefs)
                return fitCoefs[1].*(dispVals .- fitCoefs[2]).^fitCoefs[3] .- forceVals
            end
            function unloadFitMinFun(fitCoefs)
                sqrt( sum( (unloadFitFun(fitCoefs) ./ forceVals).^2 ) )
            end

            lx = [0.0, 0.0 , 0.0]; ux = [Inf, minimum(dispVals)-1e-2 , Inf];
            dfc = TwiceDifferentiableConstraints(lx, ux)
            resultFit = optimize(unloadFitMinFun, dfc, [1.0, 1.0, 1.0], IPNewton())
            uld_p = resultFit.minimizer
            stiffness_fit = uld_p[1]*uld_p[3]*(Dmax - uld_p[2]).^(uld_p[3] - 1)

        elseif cmp(hyperParameters.unloadingFitFunction, "Feng") == 0
            
            unloadFitFun2(fitCoefs) = fitCoefs[1] .+ fitCoefs[2].*forceVals.^0.5 + fitCoefs[3].*forceVals.^fitCoefs[4] .- dispVals
            unloadFitMinFun2(fitCoefs) = sqrt(sum( (unloadFitFun2(fitCoefs) ./ dispVals).^2) )
            resultFit = optimize(unloadFitMinFun2, [1.0 1.0 1.0 1.0], BFGS())
            uld_p = resultFit.minimizer
            stiffness_fit = inv(( 0.5*uld_p[2].*Fmax.^-0.5 + uld_p[4]*uld_p[3].*Fmax.^(uld_p[4] - 1.0) ))
            
        end

        h_dot_tot = determineCreepDuringHold(xy_hold,hyperParameters.sampleRate)       
        dPdt = [1/hyperParameters.sampleRate .* collect(0:(length(xy_unld5[:,1])-1)) ones(length(xy_unld5[:,1]))] \ xy_unld5[:,2]
        
        if hyperParameters.compensateCreep
            stiffness = inv(1/stiffness_fit + h_dot_tot/(abs(dPdt[1]))); 
        else
            stiffness = stiffness_fit;
        end

        # Equation (2) in [1]
        maxIndentation = median(xy_unld5[1,1]) - dhtdt*(length(xy[rampStartIdx:holdStartIdx,1])+length(xy_hold[:,1]))/hyperParameters.sampleRate;  #%OBS OBS OBS

        if cmp(indentationSet.indenterType,"pyramid") == 0
            x0 = maxIndentation - 0.72*Fmax/stiffness;
        elseif cmp(indentationSet.indenterType,"hemisphere") == 0
            x0 = maxIndentation - 0.75*Fmax/stiffness;
        end
        x0 < 0.0 && return 0.0

        area_xy = readdlm(indentationSet.areaFile, ' ', Float64, '\n')
        # % Determine the area by loading the calibration data and fitting a polynom to the data.        

        if (x0 > 100.0)
            area_fit_end = length(area_xy[:,1])
        elseif (x0 < 100.0)
            area_fit_end = findfirst( x -> x > 100,area_xy[:,1])
        end
        
        tempVec = area_xy[1:area_fit_end,1]
        p_area = [tempVec.^2 tempVec tempVec.^0.5 tempVec.^0.25 tempVec.^0.125] \ area_xy[1:area_fit_end,2]
        
        unloadArea = [x0^2 x0 x0^0.5 x0^0.25 x0^0.125] * p_area
        unloadArea = unloadArea[1]
        unloadArea < 0.0 && return 0.0
        
        # % Equation (1) in [1]
        Er = sqrt(pi)/(2.0)/sqrt(unloadArea) / (1.0/stiffness )
        if cmp(indentationSet.indenterType,"pyramid") == 0
            Er = Er/1.05;
        end
        return Er
    else
        return 0.0
    end

    println(Er)
    #return Er
end


function calculateMachineCompliance(indentationSet::metaInfoExperimentalSeries,hyperParameters,ctrl::control)
    resultNames = subdirImport(indentationSet.targetDir,".ibw");     # Find the .ibw files in targetDir
    resultNames = resultNames[6:end]
    ap = []
    bp = []
    for file in resultNames
        println(file)
        tempS , tempA = extractSingleComplianceExperiment(indentationSet,hyperParameters,ctrl,file)
        push!(ap,tempS)
        push!(bp,tempA)
        #println([tempS tempA])
    end

    squaredInverseArea = 1.0 ./sqrt.(bp)
    #return squaredInverseArea
    #return ones(size(ap))
    return [squaredInverseArea[:] ap]



    effectiveCompliance = [squaredInverseArea[:] ones(size(ap))] \ ap;
    return effectiveCompliance

    return effectiveCompliance[2]
end


function extractSingleComplianceExperiment(indentationSet::metaInfoExperimentalSeries,hyperParameters,ctrl::control,resultFile::String)
    
    
    xy = dataPreProcessing(indentationSet.targetDir*resultFile)
    # Load raw displacements

    #ctrl.plotMode && display(plot([xy[1:100:end,1]],[xy[1:100:end,2]]))

    xy , basefit , zeroLine , rampStartIdx, xZero  = offsetAndDriftCompensation(xy)
    # Find initial contact
    #ctrl.plotMode && display(plot!(xy[1:100:end,1],xy[1:100:end,2]))

    xy[:,1] .-= xy[:,2]
    xy[:,2] .*= indentationSet.springConstant
    # Convert displacement-deflection matrix to indentation-force matrix

    holdStartIdx = findStartOfHold(xy,"first")

    # Split into loading and unloading.
    xy_unld1 = xy[holdStartIdx:end,:];

    #Determine the end of the hold time.
    unloadStartIdx = findStartOfHold(xy_unld1,"last")

    # Split into two new pieces
    xy_hold = xy_unld1[1:unloadStartIdx-1,:];
    xy_unld = xy_unld1[unloadStartIdx:end,:];

    xy_unld5 = xy_unld[1:min(Int64(round(2000*0.95)),size(xy_unld,1)),:];  # OBS 2000 is hard coded!



    # Fitting of the unloading curve.
    stiffness_fit = Array{Float64}(undef,1)    
    dispVals = xy_unld5[1:min(hyperParameters.unloadingFitRange,size(xy_unld5,1)),1]
    forceVals = xy_unld5[1:min(hyperParameters.unloadingFitRange,size(xy_unld5,1)),2]
    Fmax = xy_unld5[1,2]               # Maximum force during unloading

    if cmp(hyperParameters.unloadingFitFunction,"Oliver-Pharr") == 0
        Dmax = xy_unld5[1,1]               
        # Maximum indentation depth during unloading
        
        function unloadFitFun(fitCoefs)
            return fitCoefs[1].*(dispVals .- fitCoefs[2]).^fitCoefs[3] .- forceVals
        end
        function unloadFitMinFun(fitCoefs)
            sqrt( sum( (unloadFitFun(fitCoefs) ./ forceVals).^2 ) )
        end

        lx = [-Inf, -Inf , 0.0]; ux = [Inf, minimum(dispVals)-1e-2 , Inf];
        dfc = TwiceDifferentiableConstraints(lx, ux)
        resultFit = optimize(unloadFitMinFun, dfc, [1.0, 1.0, 1.0], IPNewton())
        uld_p = resultFit.minimizer
        println(uld_p)
        stiffness_fit = uld_p[1]*uld_p[3]*(Dmax - uld_p[2]).^(uld_p[3] - 1)

    elseif cmp(hyperParameters.unloadingFitFunction, "Feng") == 0
        
        unloadFitFun2(fitCoefs) = fitCoefs[1] .+ fitCoefs[2].*forceVals.^0.5 + fitCoefs[3].*forceVals.^fitCoefs[4] .- dispVals
        unloadFitMinFun2(fitCoefs) = sqrt(sum( (unloadFitFun2(fitCoefs) ./ dispVals).^2) )
        resultFit = optimize(unloadFitMinFun2, [1.0 1.0 1.0 1.0], BFGS())
        uld_p = resultFit.minimizer
        println(uld_p)
        stiffness_fit = inv(( 0.5*uld_p[2].*Fmax.^-0.5 + uld_p[4]*uld_p[3].*Fmax.^(uld_p[4] - 1.0) ))
        
    end
    stiffness = stiffness_fit
    dhtdt = 0;

    maxIndentation = median(xy_unld5[1,1]) - dhtdt*(length(xy[rampStartIdx:holdStartIdx,1])+length(xy_hold[:,1]))/hyperParameters.sampleRate;  #%OBS OBS OBS

    if cmp(indentationSet.indenterType,"pyramid") == 0
        x0 = maxIndentation - 0.72*Fmax/stiffness;
    elseif cmp(indentationSet.indenterType,"hemisphere") == 0
        x0 = maxIndentation - 0.75*Fmax/stiffness;
    end

    area_xy = readdlm(indentationSet.areaFile, ' ', Float64, '\n')
    # % Determine the area by loading the calibration data and fitting a polynom to the data.        

    if (x0 > 100.0)
        area_fit_end = length(area_xy[:,1])
    elseif (x0 < 100.0)
        area_fit_end = findfirst( x -> x > 100,area_xy[:,1])
    end
    
    tempVec = area_xy[1:area_fit_end,1]
    p_area = [tempVec.^2 tempVec tempVec.^0.5 tempVec.^0.25 tempVec.^0.125] \ area_xy[1:area_fit_end,2]
    
    unloadArea = [x0^2 x0 x0^0.5 x0^0.25 x0^0.125] * p_area
    unloadArea = unloadArea[1]

    return 1/stiffness_fit , unloadArea
    # Assign outputs
end