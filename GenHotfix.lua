local function genCode(handler)
    local settings = handler.project:GetSettings("Publish").codeGeneration
    local codePkgName = handler:ToFilename(handler.pkg.name); --convert chinese to pinyin, remove special chars etc.
    local exportCodePath = handler.exportCodePath..'/'..codePkgName
    local namespaceName = settings.packageName

    --CollectClasses(stripeMemeber, stripeClass, fguiNamespace)
    local classes = handler:CollectClasses(settings.ignoreNoname, settings.ignoreNoname, nil)
    handler:SetupCodeFolder(exportCodePath, "cs") --check if target folder exists, and delete old files

    local getMemberByName = settings.getMemberByName

    local classCnt = classes.Count
    local writer = CodeWriter.new()
    for i=0,classCnt-1 do
        local classInfo = classes[i]
        local members = classInfo.members
        writer:reset()
        
        writer:writeln('using FairyGUI;')
        writer:writeln('using System.Threading.Tasks;')
        writer:writeln()
        writer:writeln('namespace %s', namespaceName)
        writer:startBlock()
        -- 1
        writer:writeln([[[ObjectSystem]
    public class %sAwakeSystem : AwakeSystem<%s, GObject>
    {
        public override void Awake(%s self, GObject go)
        {
            self.Awake(go);
        }
    }
        ]],classInfo.className,classInfo.className,classInfo.className)

        writer:writeln([[public sealed class %s : FUI
    {	
        public const string UIPackageName = "%s";
        public const string UIResName = "%s";
        
        /// <summary>
        /// {uiResName}的组件类型(GComponent、GButton、GProcessBar等)，它们都是GObject的子类。
        /// </summary>
        public %s self;
            ]],classInfo.className,codePkgName,classInfo.resName,classInfo.superClassName)

        local memberCnt = members.Count
        for j=0,memberCnt-1 do
            local memberInfo = members[j]
            writer:writeln('public %s %s;', memberInfo.type, memberInfo.varName)
        end
        writer:writeln('public const string URL = "ui://%s%s";', handler.pkg.id, classInfo.resId)
        writer:writeln()

        writer:writeln([[private static GObject CreateGObject()
    {
        return UIPackage.CreateObject(UIPackageName, UIResName);
    }
    
    private static void CreateGObjectAsync(UIPackage.CreateObjectCallback result)
    {
        UIPackage.CreateObjectAsync(UIPackageName, UIResName, result);
    }
        ]])

        writer:writeln([[public static %s CreateInstance(Entity domain)
    {			
        return EntityFactory.Create<%s, GObject>(domain, CreateGObject());
    }
        ]],classInfo.className,classInfo.className)

        writer:writeln([[public static Task<%s> CreateInstanceAsync(Entity domain)
    {
        TaskCompletionSource<%s> tcs = new TaskCompletionSource<%s>();

        CreateGObjectAsync((go) =>
        {
            tcs.SetResult(EntityFactory.Create<%s, GObject>(domain, go));
        });

        return tcs.Task;
    }
        ]],classInfo.className,classInfo.className,classInfo.className,classInfo.className)

        writer:writeln([[public static %s Create(Entity domain, GObject go)
    {
        return EntityFactory.Create<%s, GObject>(domain, go);
    }
        ]],classInfo.className,classInfo.className)

        writer:writeln([[/// <summary>
    /// 通过此方法获取的FUI，在Dispose时不会释放GObject，需要自行管理（一般在配合FGUI的Pool机制时使用）。
    /// </summary>
    public static %s GetFormPool(Entity domain, GObject go)
    {
        var fui = go.Get<%s>();

        if(fui == null)
        {
            fui = Create(domain, go);
        }

        fui.isFromFGUIPool = true;

        return fui;
    }
        ]],classInfo.className,classInfo.className)

            writer:writeln([[public void Awake(GObject go)
    {
        if(go == null)
        {
            return;
        }
        
        GObject = go;	
        
        if (string.IsNullOrWhiteSpace(Name))
        {
            Name = Id.ToString();
        }
        
        self = (%s)go;
        
        self.Add(this);
        
        var com = go.asCom;
            
        if(com != null)
        {	
            ]],classInfo.superClassName)

        for j=0,memberCnt-1 do
            local memberInfo = members[j]
            local typeName = memberInfo.type
            if memberInfo.group==0 then
                if getMemberByName then
                    -- 判断是不是我们自定义类型
                    local isCustomComponent = false
                    for i = 0, classCnt - 1 do
                        if typeName == classes[i].className then
                            isCustomComponent = true
                            break
                        end
                    end
                    if isCustomComponent then
                        writer:writeln('\t\t%s = %s.Create(domain, com.GetChild("%s"));', memberInfo.varName, memberInfo.type, memberInfo.name)
                    else
                        writer:writeln('\t\t%s = (%s)com.GetChild("%s");', memberInfo.varName, memberInfo.type, memberInfo.name)
                    end
                else
                    local isCustomComponent = false
                    for i = 0, classCnt - 1 do
                        if typeName == classes[i].className then
                            isCustomComponent = true
                            break
                        end
                    end
                    if isCustomComponent then
                        writer:writeln('\t\t%s = %s.Create(domain, com.GetChildAt(%s));', memberInfo.varName, memberInfo.type, memberInfo.index)
                    else
                        writer:writeln('\t\t%s = (%s)com.GetChildAt(%s);', memberInfo.varName, memberInfo.type, memberInfo.index)
                    end
                end
            elseif memberInfo.group==1 then
                if getMemberByName then
                    writer:writeln('\t\t%s = com.GetController("%s");', memberInfo.varName, memberInfo.name)
                else
                    writer:writeln('\t\t%s = com.GetControllerAt(%s);', memberInfo.varName, memberInfo.index)
                end
            else
                if getMemberByName then
                    writer:writeln('\t\t%s = com.GetTransition("%s");', memberInfo.varName, memberInfo.name)
                else
                    writer:writeln('\t\t%s = com.GetTransitionAt(%s);', memberInfo.varName, memberInfo.index)
                end
            end
        end
        writer:writeln('\t}')

        writer:endBlock()

            writer:writeln([[       public override void Dispose()
       {
            if(IsDisposed)
            {
                return;
            }
            
            base.Dispose();
            
            self.Remove();
            self = null;
            ]])

        for j=0,memberCnt-1 do
            local memberInfo = members[j]
            local typeName = memberInfo.type
            if memberInfo.group==0 then
                if getMemberByName then
                    if string.find(typeName,'FUI') then
                        writer:writeln('\t\t\t%s.Dispose();', memberInfo.varName)
                    end
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                else
                    if string.find(typeName,'FUI') then
                        writer:writeln('\t\t\t%s.Dispose();', memberInfo.varName)
                    end
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                end
            elseif memberInfo.group==1 then
                if getMemberByName then
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                else
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                end
            else
                if getMemberByName then
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                else
                    writer:writeln('\t\t\t%s = null;', memberInfo.varName)
                end
            end
        end
        writer:writeln('\t\t}')

        writer:endBlock() --class
        writer:endBlock() --namepsace

        writer:save(exportCodePath..'/'..classInfo.className..'.cs')
    end

    -- 写入fuipackage
    writer:reset()

    writer:writeln('namespace %s', namespaceName)
    writer:startBlock()
    writer:writeln('public static partial class FUIPackage')
    writer:startBlock()

    writer:writeln('public const string %s = "%s";',codePkgName,codePkgName)

    -- 生成所有的
    local itemCount = handler.items.Count
    for i=0,itemCount-1 do
        writer:writeln('public const string %s_%s = "ui://%s/%s";',codePkgName,handler.items[i].name,codePkgName,handler.items[i].name)
    end


    writer:endBlock() --class
    writer:endBlock() --namespace
    local binderPackageName = 'Package'..codePkgName
    writer:save(exportCodePath..'/'..binderPackageName..'.cs')
end

return genCode
