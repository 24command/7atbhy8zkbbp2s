#pragma once
#include <string>
#include <vector>
#include <cstdint>
namespace pmfullshader {
struct Uniform {std::string name;uint32_t offset=0,rows=1,columns=1,arrayCount=1,arrayStride=0,matrixStride=0;enum Scalar{Float,Int,UInt,Bool}scalar=Float;std::vector<float>defaults;};
struct Program {std::string msl;std::string entry;size_t uniformBytes=0;std::vector<Uniform>uniforms;};
Program compile(const std::string&source);
std::vector<uint8_t> defaults(const Program&);
void put(std::vector<uint8_t>&,const Uniform&,unsigned component,double value);
}
