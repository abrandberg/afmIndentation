
function ReadIBW(filename,folder)

cd(folder)
A = open(read, filename)

firstByte = A[1]

firstByte == 0
if firstByte == 0
    machineFormat = 'b'
else
    machineFormat = 'l'
end

# Check version
version = read(filename, Int16)
