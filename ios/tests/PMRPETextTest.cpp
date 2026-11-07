#include "../PhiMod/Core/PMRPEText.hpp"
#include <cassert>
int main(){
 assert(rpeTextTween("","abcd",.5f)=="ab");
 assert(rpeTextTween("abcd","",.5f)=="ab");
 assert(rpeTextTween("ab","abcd",.5f)=="abc");
 assert(rpeTextTween("abcd","ab",.5f)=="abc");
 assert(rpeTextTween("1%P%","100%P%",.5f)=="50");
 assert(rpeTextTween("1.5%P%","2.5%P%",.5f)=="2.000");
 std::string unicode="\xe4\xbd\xa0\xe5\xa5\xbd\xf0\x9f\x98\x80";
 assert(rpeTextTween("",unicode,1)==unicode);
 assert(rpeTextTween("",unicode,.66f)==unicode.substr(0,6));
 assert(rpeTextTween("<test>","<test>",.5f)=="<test>");
 assert(rpeTextTween("a\nb","a\nb",.5f)=="a\nb");
 assert(rpeTextTween("0%P%","100%P%",1)=="100");
}
