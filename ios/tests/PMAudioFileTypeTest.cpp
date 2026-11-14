#include "../PhiMod/Core/PMAudioFileType.hpp"
#include <cassert>
#include <cstring>
int main(){
 auto check=[](const char*p,size_t n,const char*expected){assert(!std::strcmp(phimod::audioFileExtension(reinterpret_cast<const unsigned char*>(p),n),expected));};
 check("RIFF1234WAVE",12,"wav");check("OggS",4,"ogg");check("fLaC",4,"flac");check("1234ftypM4A ",12,"m4a");check("FORM1234AIFF",12,"aiff");check("ID3",3,"mp3");
 const unsigned char mp3[]={0xff,0xfb,0xe4,0x44};assert(!std::strcmp(phimod::audioFileExtension(mp3,4),"mp3"));
 check("RIFF",4,"");check("",0,"");check("not audio",9,"");
 const unsigned char aac[]={0xff,0xf1,0x50,0x80};assert(!*phimod::audioFileExtension(aac,4));
}
