// Bounded, observational render-pass trace. Never changes pass descriptors or textures.
std::atomic<bool>traceEnabled{false};std::atomic<unsigned>traceFrames{0};
NSString*tracePath=nil;NSMutableArray*traceRecords=nil;static char tracePassKey;
void traceReset(){traceEnabled=false;traceFrames=0;tracePath=nil;traceRecords=nil;}
void traceBegin(NSString*folder){tracePath=[folder stringByAppendingPathComponent:@"shader-render-stages-ios.json"];traceRecords=[NSMutableArray new];traceFrames=0;traceEnabled=true;}
NSDictionary*traceTexture(id<MTLTexture>t){if(!t)return @{};return @{@"id":[NSString stringWithFormat:@"%p",(__bridge void*)t],@"label":t.label?:@"",@"width":@(t.width),@"height":@(t.height),@"format":@(t.pixelFormat),@"samples":@(t.sampleCount),@"usage":@(t.usage),@"storage":@(t.storageMode),@"framebufferOnly":@(t.framebufferOnly)};}
void tracePass(id buffer,MTLRenderPassDescriptor*pass){
 if(!traceEnabled.load()||!pass||chartTime.load()<0)return;
 @try{@synchronized(buffer){NSMutableArray*records=objc_getAssociatedObject(buffer,&tracePassKey);if(!records){records=[NSMutableArray new];objc_setAssociatedObject(buffer,&tracePassKey,records,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}if(records.count>=96)return;
  NSMutableArray*colors=[NSMutableArray new];for(NSUInteger i=0;i<8;++i){MTLRenderPassColorAttachmentDescriptor*a=pass.colorAttachments[i];if(a.texture)[colors addObject:@{@"slot":@(i),@"texture":traceTexture(a.texture),@"resolve":traceTexture(a.resolveTexture),@"load":@(a.loadAction),@"store":@(a.storeAction),@"level":@(a.level),@"slice":@(a.slice)}];}
  [records addObject:@{@"colors":colors,@"depth":traceTexture(pass.depthAttachment.texture),@"stencil":traceTexture(pass.stencilAttachment.texture)}];
 }}@catch(NSException*exception){(void)exception;}
}
void tracePresent(id<MTLCommandBuffer>buffer,id<MTLDrawable>drawable){
 if(!traceEnabled.load()||![drawable conformsToProtocol:@protocol(CAMetalDrawable)])return;
 id<CAMetalDrawable>metal=(id<CAMetalDrawable>)drawable;std::lock_guard<std::mutex>guard(stateLock);
 if(!traceEnabled.load()||metal.layer!=gameLayer||buffer.device!=device||chartTime.load()<0)return;
 unsigned frame=traceFrames.fetch_add(1);if(frame>=8)return;
 NSArray*passes=nil;@synchronized(buffer){passes=[objc_getAssociatedObject(buffer,&tracePassKey)copy];objc_setAssociatedObject(buffer,&tracePassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
 [traceRecords addObject:@{@"frame":@(frame),@"time":@(chartTime.load()),@"bufferLabel":buffer.label?:@"",@"drawable":traceTexture(metal.texture),@"passes":passes?:@[]}];
 if(frame==7){traceEnabled=false;NSString*path=[tracePath copy];NSDictionary*output=@{@"version":@1,@"observationalOnly":@YES,@"limitation":@"Only passes on presented command buffers; cameras/layer identity requires device correlation. No inferred shader boundary.",@"frames":[traceRecords copy]};
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{NSError*error=nil;NSData*data=[NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:&error];if(data&&[data writeToFile:path options:NSDataWritingAtomic error:&error])report([@"Shader render trace saved: " stringByAppendingString:path]);else report([NSString stringWithFormat:@"Shader render trace failed: %@",error.localizedDescription]);});
 }
}
