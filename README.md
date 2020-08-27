# ZZZombie
#实现方案
1.hook dealloc方法 2.在替换的dealloc方法里 构造一个包含isa的对象（仅有处理消息转发的方法） 将dealloc对象的isa赋给构造的对象 同时用跑步机结构存储该对象 3.当有消息发送给dealloc对象时 触发构造对象的消息转发；然后可以进行crash收集（待实现）。
#用法
1.开启野指针收集：ObjcEvilDoers::SimpleZombieEnable(bool zombieAllObjects, size_t zombieCount);zombieAllObjects是否对所有对象都开启 zombieCount最大存储dealloc对象的数量
2.关闭野指针收集：ObjcEvilDoers::SimpleZombieDisable
