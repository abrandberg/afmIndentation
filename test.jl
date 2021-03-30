function [data, dUnits, x0, dx, xUnits] = ReadIBW(filename,folder)
#
# DEFINITION
# Reads Igor's [Wavemetric] binary wave format, .ibw, files.
#
# INPUT
# filename: string giving the filename ending in .ibw
# folder: string description of emplacement of file.
#
# OUTPUT
# data: vector [single precision] of values of the wave containted in the file
# dUnits: string: saved values of the units of data [char].
#
# ALGORITHM
# Uses fread & the parsing proper to version 2; 3; | version 5 (see Technical notes TN003.ifn:
# http://mirror.optus.net.au/pub/wavemetrics/IgorPro/Technical_Notes/) & data
# type 2 or 4 [non complex, single | double precision vector, real values].
#
# - R. Naud August 2008


####################### go to directory
if nargin >1
    cd(folder)
end

####################### ORDERING
#[fid, message] = fopen(filename, permission, machineformat)
# machine format ie: "ieee�be" ; for IEEE floating point with big-endian
# byte ordering
#MacIgor use the Motorola big-endian 'b'
#WinIgor use Intel little-endian 'l'
#  If the first byte in the file is non-zero; then the file is a WinIgor
[fid, message] = fopen(filename,'r')
FirstByte = fread(fid,1,"int8")
fclose(fid)
if FirstByte ==0
    machineformat = 'b'
else()
    machineformat = 'l'
end

#######################  CHECK VERSION
[fid, message] = fopen(filename,'r',machineformat)
version = fread(fid,1,"int16")
fclose(fid)

#######################  READ DATA AND ACCOMPANYING INFO
[fid, message] = fopen(filename,'r',machineformat)
if version .== 2

    # pre header
    version = fread(fid,1,"int16")
    wfmSize = fread(fid,1,"int32"); # The size of the WaveHeader2 data structure plus the wave data plus 16 bytes of padding.
    noteSize = fread(fid,1,"int32"); # The size of the note text.
    pictSize = fread(fid,1,"int32"); # Reserved. Write zero. Ignore on read.
    checksum = fread(fid,1,"uint16"); #  Checksum over this header & the wave header.

    # wave header
    type = fread(fid,1,"int16")
    if type .== 2
        datatype = "single"
    elseif type .== 4
        datatype = "double"
    else()
        disp(["wave is of type ',num2str(type), ', not supported"])
        return
    end
    ignore = fread(fid,1,"uint32")
    bname = char(fread(fid,20,"char')")
    ignore = fread(fid,2,"int16")
    ignore = fread(fid,1,"uint32")
    dUnits = char(fread(fid,4,"char')")
    xUnits = char(fread(fid,4,"char')")
    npnts = fread(fid,1,"int32")
    amod = fread(fid,1,"int16")
    dx = fread(fid,1,"double")
    x0 = fread(fid,1,"double")
    ignore = fread(fid,2,"int16")
    fsValid = fread(fid,1,"int16")
    topFullScale = fread(fid,1,"double")
    botFullScale = fread(fid,1,"double")
    ignore = fread(fid,16,"int8")
    modDate = fread(fid,1,"uint32")
    creationDate = fread(fid,1,"uint32")
    wdata = fread(fid,npnts,datatype)
    x0 = double(x0*fsValid)
    dx = double(dx*fsValid)


elseif version .== 3 # NOT CHECKED!! IF PB; REFER TO IGORBIN.H IN TN003.ZIP


    # pre header
    version = fread(fid,1,"int16")
    wfmSize = fread(fid,1,"int32"); # The size of the WaveHeader2 data structure plus the wave data plus 16 bytes of padding.
    noteSize = fread(fid,1,"int32"); # The size of the note text.
    formulaSize = fread(fid,1,"int32")
    pictSize = fread(fid,1,"int32"); # Reserved. Write zero. Ignore on read.
    checksum = fread(fid,1,"uint16"); #  Checksum over this header & the wave header.

    # wave header
    type = fread(fid,1,"int16")
    if type .== 2
        datatype = "single"
    elseif type .== 4
        datatype = "double"
    else()
        disp(["wave is of type ',num2str(type), ', not supported"])
        return
    end
    ignore = fread(fid,1,"uint32")
    bname = char(fread(fid,20,"char')")
    ignore = fread(fid,2,"int16")
    ignore = fread(fid,1,"uint32")
    dUnits = char(fread(fid,4,"char')")
    xUnits = char(fread(fid,4,"char')")
    npnts = fread(fid,1,"int32")
    amod = fread(fid,1,"int16")
    dx = fread(fid,1,"double")
    x0 = fread(fid,1,"double")
    ignore = fread(fid,2,"int16")
    fsValid = fread(fid,1,"int16")
    topFullScale = fread(fid,1,"double")
    botFullScale = fread(fid,1,"double")
    ignore = fread(fid,16,"int8")
    modDate = fread(fid,1,"uint32")
    creationDate = fread(fid,1,"uint32")
    wdata = fread(fid,npnts,datatype)

    x0 = double(x0*fsValid)
    dx = double(dx*fsValid)

elseif version .== 5
    # pre header
    version = fread(fid,1,"int16")
    checksum = fread(fid,1,"uint16"); #  Checksum over this header & the wave header.
    wfmSize = fread(fid,1,"int32"); # The size of the WaveHeader2 data structure plus the wave data plus 16 bytes of padding.
    formulaSize = fread(fid,1,"int32"); #
    noteSize = fread(fid,1,"int32"); # The size of the note text.
    dataEUnitsSize =  fread(fid,1,"int32"); #
    dimEUnitsSize=  fread(fid,4,"int32"); #
    dimLabelsSize =  fread(fid,4,"int32"); #
    sIndicesSize =  fread(fid,1,"int32"); #
    optionSize1 =  fread(fid,1,"int32"); #
    optionSize2 =  fread(fid,1,"int32"); #

    # header
    ignore =  fread(fid,1,"int32"); #
    CreationDate =  fread(fid,1,"uint32"); #
    modData =  fread(fid,1,"uint32"); #
    npnts =  fread(fid,1,"int32"); #
    type = fread(fid,1,"int16")
    if type .== 2
        datatype = "single"
    elseif type .== 4
        datatype = "double"
    else()
        disp(["wave is of type ',num2str(type), ', not supported"])
        return
    end

    ignore = fread(fid,1,"int16"); #
    ignore = fread(fid,6,"schar"); #
    ignore = fread(fid,1,"int16"); #
    bname = char(fread(fid,32, "char'))"
    ignore = fread(fid,1,"int32"); #
    ignore = fread(fid,1,"int32"); #
    ndims = fread(fid,4,"int32"); # Number of of items in a dimension -- 0 means no data.
    sfA = fread(fid,4,"double"); #
    sfB  = fread(fid,4,"double"); #
    dUnits = char(fread(fid,4,"char'))"
    xUnits = char(fread(fid,4*4, "char'))"
    fsValid = fread(fid,1,"int16"); #
    whpad3 = fread(fid,1,"int16"); #
    ignore = fread(fid,2,"double"); #
    ignore = fread(fid,10,"int32")
    ignore = fread(fid,16,"int32")
    ignore = fread(fid,3,"int16")
    ignore = fread(fid,2,"char")
    ignore = fread(fid,1,"int32")
    ignore = fread(fid,2,"int16")
    ignore = fread(fid,1,"int32")
    modDate = fread(fid,1,"int32")
    creationDate = fread(fid,1,"int32")
    wdata = fread(fid,npnts,datatype); #

    x0 = double(sfB[1]*fsValid)
    dx = double(sfA[1]*fsValid)


else()
       disp(["wave is in version ',num2str(version), ', not supported"])
       data = []
       dUnits = []
       return
end

data = wdata

fclose(fid)

end
