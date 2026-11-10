#include "../PhiMod/Core/PMPCMImport.hpp"
#include <cassert>
#include <filesystem>
#include <iterator>
#include <cstring>
#include <iostream>
#include <sstream>
static void put64(std::ostream&o,uint64_t v){pmpcm::put32(o,uint32_t(v));pmpcm::put32(o,uint32_t(v>>32));}
std::vector<uint8_t>load(const std::filesystem::path&p){std::ifstream f(p,std::ios::binary);return {std::istreambuf_iterator<char>(f),std::istreambuf_iterator<char>()};}
void fixture(const std::filesystem::path&path,unsigned width,unsigned channels,int codec){
 std::cout<<"fixture width="<<width<<" channels="<<channels<<" codec="<<codec<<std::endl;
 const size_t n=262144+128;std::vector<uint8_t>raw(n);
 for(size_t i=0;i<n;i+=width){uint32_t bits;if(width==2)bits=uint16_t((i/width)%300-150);else{float x=float((i/width)%50)/100;std::memcpy(&bits,&x,4);}for(unsigned k=0;k<width;++k)raw[i+k]=uint8_t(bits>>(8*k));}
 std::ofstream f(path,std::ios::binary);uint32_t c=width==4?uint32_t(0-channels):channels;
 if(codec<0){pmpcm::put32(f,48000);pmpcm::put32(f,width==2?uint32_t(0-channels):channels);f.write((char*)raw.data(),raw.size());}
 else{
  struct Entry{uint64_t offset;uint32_t stored,raw,codec,crc;};std::vector<Entry>entries;
  f.write("PHIPCMZ1",8);pmpcm::put32(f,48000);pmpcm::put32(f,c);put64(f,n/(channels*width));pmpcm::put32(f,131072);pmpcm::put32(f,3);put64(f,0);
  for(size_t offset=0;offset<n;offset+=131072){size_t count=std::min(size_t(131072),n-offset);std::vector<uint8_t>filtered(count),compressed(count+256);const uint8_t*data=raw.data()+offset;
   if(codec==2){uint32_t previous[2]={};size_t samples=count/width;for(size_t i=0;i<samples;++i){uint32_t value=0;for(unsigned k=0;k<width;++k)value|=uint32_t(data[i*width+k])<<(8*k);uint32_t delta=value-previous[i%channels];previous[i%channels]=value;for(unsigned k=0;k<width;++k)filtered[k*samples+i]=uint8_t(delta>>(8*k));}data=filtered.data();}
   mz_ulong bytes=compressed.size();if(codec)assert(mz_compress2(compressed.data(),&bytes,data,count,6)==MZ_OK);else{std::copy_n(data,count,compressed.begin());bytes=count;}
   int actualCodec=codec;if(bytes>=count){std::copy_n(raw.data()+offset,count,compressed.begin());bytes=count;actualCodec=0;}
   entries.push_back({uint64_t(f.tellp()),uint32_t(bytes),uint32_t(count),uint32_t(actualCodec),uint32_t(mz_crc32(0,raw.data()+offset,count))});f.write((char*)compressed.data(),bytes);
  }
  uint64_t index=uint64_t(f.tellp());for(auto&e:entries){put64(f,e.offset);pmpcm::put32(f,e.stored);pmpcm::put32(f,e.raw);pmpcm::put32(f,e.codec);pmpcm::put32(f,e.crc);}f.seekp(32);put64(f,index);
 }
 f.close();auto wav=path;wav+=".wav";auto info=pmpcm::toWav(path.string().c_str(),wav.string().c_str());auto bytes=load(wav);
 assert(info.channels==channels&&info.width==width&&info.bytes==raw.size());assert(bytes.size()==44+raw.size());assert(std::equal(raw.begin(),raw.end(),bytes.begin()+44));
 if(codec>=0){auto corrupt=load(path);corrupt.back()^=1;std::ofstream bad(path,std::ios::binary|std::ios::trunc);bad.write((char*)corrupt.data(),corrupt.size());bad.close();bool rejected=false;try{pmpcm::toWav(path.string().c_str(),wav.string().c_str());}catch(const std::runtime_error&){rejected=true;}assert(rejected);}
 std::filesystem::remove(path);std::filesystem::remove(wav);
}
int main(int argc,char**argv){try{assert(argc==2);std::filesystem::path base=argv[1];for(unsigned width:{2u,4u})for(unsigned channels:{1u,2u})for(int codec:{-1,0,1,2})fixture(base/("pcm-"+std::to_string(width)+"-"+std::to_string(channels)+"-"+std::to_string(codec)),width,channels,codec);
 bool rejected=false;std::istringstream invalid(std::string(40,'\0'));try{pmpcm::inspect(invalid,40);}catch(const std::runtime_error&){rejected=true;}assert(rejected);
 std::cout<<"PASS 16 PCM mono/stereo integer/float legacy/packed round trips, filtered blocks and CRC rejection\n";
}catch(const std::exception&e){std::cerr<<e.what()<<std::endl;return 1;}
}
