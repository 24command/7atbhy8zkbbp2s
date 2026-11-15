from pathlib import Path
import os,shutil,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text('utf8')
def extract(start,end):return SOURCE.split(start,1)[1].split(end,1)[0]
def fixture():
 field='P field('+extract('P field(','template<class T> T staticValue(')
 read='template<class T> void checkReadField('+extract('template<class T> void checkReadField(','template<class T> void put(')
 return r"""
#include <map>
#include <set>
#include <tuple>
#include <string>
#include <stdexcept>
#include <cstring>
#include <cassert>
#include <type_traits>
using P=void*;
struct Field{bool isStatic;const char*type;};
struct Object{int value;};
struct Bridge{
 Field integer{false,"System.Int32"},single{false,"System.Single"};int lookups=0,types=0,checks=0,reads=0;
 std::map<std::tuple<P,std::string,std::string,bool>,P>validatedFields;
 std::set<std::pair<P,const void*>>checkedReadFields;
 P class_get_field_from_name(P c,const char*name){++lookups;return !strcmp(name,"value")?c:nullptr;}
 int field_get_flags(P f){return ((Field*)f)->isStatic?0x10:0;}
 P field_get_type(P f){++types;return f;}
 P class_from_type(P f){return f;}
 bool typeIs(P f,const char*t){return !strcmp(((Field*)f)->type,t);}
 template<class T>void checkClass(P f){++checks;const char*t=std::is_same<T,int>::value?"System.Int32":"System.Single";if(!typeIs(f,t))throw std::runtime_error("bad read type");}
 P objectField(P,const char*){return &integer;}
 void field_get_value(P obj,P,void*out){++reads;*(int*)out=((Object*)obj)->value;}
"""+field+read+r"""
};
int main(){Bridge b;Object a{1},other{77};
 for(int i=0;i<10000;++i){a.value=i;assert(b.field(&b.integer,"value","System.Int32",false)==&b.integer);assert(b.get<int>(&a,"value")==i);}assert(b.lookups==1&&b.checks==1&&b.reads==10000);assert(b.get<int>(&other,"value")==77);
 for(int i=0;i<2;++i){bool failed=false;try{b.field(&b.integer,"value","System.Single",false);}catch(...){failed=true;}assert(failed);}
 bool failed=false;try{b.field(&b.integer,"value","System.Int32",true);}catch(...){failed=true;}assert(failed);
 assert(b.field(&b.single,"value","System.Single",false)==&b.single);
 size_t validated=b.checkedReadFields.size();for(int i=0;i<2;++i){failed=false;try{b.checkReadField<float>(&b.integer);}catch(...){failed=true;}assert(failed&&b.checkedReadFields.size()==validated);}
 b.checkReadField<float>(&b.single);assert(b.checkedReadFields.size()==validated+1);
 Bridge second;assert(second.get<int>(&other,"value")==77&&second.checks==1);
}
"""
class MetadataCacheTest(unittest.TestCase):
 def test_only_successful_metadata_validation_is_cached(self):
  block=extract('template<class T> void checkReadField(','template<class T> T get(')
  self.assertLess(block.index('checkClass<T>'),block.index('checkedReadFields.insert'))
  get=extract('template<class T> T get(','template<class T> void put(')
  self.assertIn('field_get_value(obj,f,&v)',get)
 def test_production_cpp_metadata_cache(self):
  cxx=os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++')
  if not cxx:self.skipTest('C++ compiler not on PATH')
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);cpp=root/'cache.cpp';cpp.write_text(fixture(),'utf8');exe=root/('cache.exe' if os.name=='nt' else 'cache')
   subprocess.run([cxx,'-std=c++17','-O2',str(cpp),'-o',str(exe)],check=True,capture_output=True)
   subprocess.run([str(exe)],check=True)
if __name__=='__main__':unittest.main()
