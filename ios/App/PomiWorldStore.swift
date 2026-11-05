import Foundation
import Combine
import Security
import PetDomain

/// Server owns real inventory. Preview has an independent, atomic local save.
@MainActor final class PomiWorldStore: ObservableObject {
    @Published private(set) var inventory = PomiInventory()
    @Published private(set) var busy = false
    @Published var message = ""
    @Published var serviceURL = UserDefaults.standard.string(forKey:"pomi.serviceURL") ?? ""
    @Published private(set) var preview = false
    private var token: String?
    private let previewURL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NucleoPet/world-preview.json")
    private var identityHost: String?
    private var configured=false

    func configure(preview: Bool) {
        guard !configured || self.preview != preview else { return }
        configured=true;self.preview=preview;token=nil;identityHost=nil;inventory=PomiInventory()
        if preview {
            do {
                if AppRuntime.isUITesting && ProcessInfo.processInfo.arguments.contains("--reset-demo") { inventory = .preview();try persistPreview() }
                else if FileManager.default.fileExists(atPath:previewURL.path) { inventory=try JSONDecoder().decode(PomiInventory.self,from:Data(contentsOf:previewURL)) }
                else { inventory = .preview();try persistPreview() }
                message="独立预览 · 放生海中的瓶子为模拟内容"
            } catch { message="预览仓库无法读取，原文件已保留：\(error.localizedDescription)" }
        } else { message="请设置小屋服务地址，连接后加载真实仓库" }
    }
    private func persistPreview() throws {
        try FileManager.default.createDirectory(at:previewURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(inventory).write(to:previewURL,options:.atomic)
    }
    private func credential(_ host: String, value: String? = nil) throws -> String? {
        let key: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"Pomi.World",kSecAttrAccount as String:host]
        if let value {
            let data=Data(value.utf8)
            let status=SecItemUpdate(key as CFDictionary,[kSecValueData as String:data] as CFDictionary)
            if status==errSecItemNotFound {
                var add=key;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw PhysicalError.message("无法安全保存身份，请勿继续创建仓库") }
            } else if status != errSecSuccess { throw PhysicalError.message("无法安全保存身份") }
            return value
        }
        var query=key;query[kSecReturnData as String]=true
        var result: CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess,let data=result as? Data,let text=String(data:data,encoding:.utf8) else { throw PhysicalError.message("无法读取安全身份") }
        return text
    }
    private func baseURL() throws -> URL {
        let text=serviceURL.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let u=URL(string:text),let host=u.host,u.user==nil,u.password==nil,u.query==nil,u.fragment==nil,
              u.path.isEmpty || u.path=="/" else { throw PhysicalError.message("请输入完整服务地址，如 https://pomi.example.com") }
        let local=host=="localhost" || host=="127.0.0.1" || host.hasSuffix(".local")
        guard u.scheme=="https" || (local && u.scheme=="http") else { throw PhysicalError.message("线上服务需要 HTTPS；Mac 本地调试可用 .local 地址") }
        var parts=URLComponents(url:u,resolvingAgainstBaseURL:false)
        parts?.scheme=u.scheme?.lowercased();parts?.host=host.lowercased();parts?.path=""
        guard let canonical=parts?.url else { throw PhysicalError.message("服务地址无效") }
        return canonical
    }
    private func send(_ path: String, body: [String:Any], auth: Bool = true) async throws -> Data {
        let base=try baseURL()
        var request=URLRequest(url:base.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod="POST";request.timeoutInterval=15;request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if auth,let token { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (data,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200 else {
            let error=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            if let status=(response as? HTTPURLResponse)?.statusCode,status>=400,status<500,auth,path != "/state" {
                _ = try credential(base.absoluteString+"/outbox",value:"")
            }
            throw PhysicalError.message(error ?? "小屋服务暂时无法连接，请稍后重试")
        }
        return data
    }
    func connect() async {
        guard !preview,!busy else { return };busy=true;defer{busy=false}
        do {
            let host=try baseURL().absoluteString
            if identityHost != host { token=try credential(host);identityHost=host }
            if token==nil {
                struct Identity: Decodable { let token:String }
                let data=try await send("/identity",body:[:],auth:false)
                let new=try JSONDecoder().decode(Identity.self,from:data).token
                token=try credential(host,value:new)
            }
            // Replay an ambiguous network mutation with its original request ID first.
            if let saved=try credential(host+"/outbox"),!saved.isEmpty,
               let data=saved.data(using:.utf8),let out=try JSONSerialization.jsonObject(with:data) as? [String:Any],
               let path=out["path"] as? String,let body=out["body"] as? [String:Any] {
                _ = try await send(path,body:body)
                _ = try credential(host+"/outbox",value:"")
            }
            inventory=try JSONDecoder().decode(PomiInventory.self,from:await send("/state",body:[:]))
            UserDefaults.standard.set(serviceURL,forKey:"pomi.serviceURL");message="真实仓库已同步"
        } catch { message=error.localizedDescription }
    }
    @discardableResult func perform(_ path: String, _ body: [String:Any] = [:], requestID: String = UUID().uuidString) async throws -> PomiInventory {
        guard !busy else { throw PhysicalError.message("正在同步，请稍后") }
        busy=true;defer{busy=false}
        if preview {
            let old=inventory
            do {
                try applyPreview(path,body);try persistPreview()
                message = path=="/fish" ? "预览：捞到的物品已放入仓库" : path=="/release" ? "预览：漂流瓶已经出发" : path=="/settle" ? "预览：挂件操作已完成，仓库已更新" : "预览仓库已更新"
                return inventory
            }
            catch { inventory=old;throw error }
        }
        guard token != nil,identityHost == (try baseURL().absoluteString) else { throw PhysicalError.message("请先连接小屋服务") }
        let host=try baseURL().absoluteString
        if let saved=try credential(host+"/outbox"),!saved.isEmpty { throw PhysicalError.message("上一次联网操作待确认，请点连接并同步仓库恢复") }
        var b=body;b["requestID"]=requestID
        let out=try JSONSerialization.data(withJSONObject:["path":path,"body":b])
        _ = try credential(host+"/outbox",value:String(decoding:out,as:UTF8.self))
        let data=try await send(path,body:b)
        let next=try JSONDecoder().decode(PomiInventory.self,from:data)
        _ = try credential(host+"/outbox",value:"")
        inventory=next
        message="仓库已同步";return inventory
    }
    private func applyPreview(_ path:String,_ b:[String:Any]) throws {
        func item() throws -> PomiItem {
            guard let i=inventory.items.first(where:{$0.id==b["itemID"] as? String}),!inventory.room.values.contains(i.id),inventory.pending?.itemID != i.id else { throw PhysicalError.message("物品正在使用中，请先收回") };return i
        }
        switch path {
        case "/activity": inventory.boxes.append(UUID().uuidString);inventory.note("模拟散步带回一个盒子")
        case "/prepare":
            guard inventory.pending==nil else { throw PhysicalError.message("请先完成待确认操作") }
            let kind=b["kind"] as? String ?? ""
            let i=kind=="food" ? try item() : nil
            if kind=="open" { guard inventory.boxes.contains(b["boxID"] as? String ?? "") else { throw CompanionError.invalidState } }
            if kind=="food",i?.kind != "berry" { throw CompanionError.invalidState }
            inventory.pending = PomiOperation(id:UUID().uuidString,kind:kind,boxID:b["boxID"] as? String,itemID:i?.id,petID:b["petID"] as? String ?? "",reward:kind=="open" ? .init(kind:inventory.catalog.randomElement()!.id) : nil,level:i?.level ?? 1)
        case "/settle":
            guard let p=inventory.pending,p.id==b["operationID"] as? String else { throw CompanionError.invalidState }
            if p.kind=="open",let reward=p.reward { inventory.boxes.removeAll{$0==p.boxID};inventory.items.append(reward);inventory.note("模拟开盒得到新物品") }
            else { inventory.items.removeAll{$0.id==p.itemID};inventory.note("模拟挂件按键确认了点心") }
            inventory.pending=nil
        case "/decorate": try inventory.decorate(b["itemID"] as? String,slot:b["slot"] as? String ?? "")
        case "/merge": try inventory.merge(b["itemID"] as? String ?? "")
        case "/release": let i=try item();inventory.items.removeAll{$0.id==i.id};inventory.note("模拟物品漂向了海面")
        case "/fish":
            let now=Date().timeIntervalSince1970
            if inventory.nextChanceAt==0 { inventory.nextChanceAt=now+10800 }
            if now>=inventory.nextChanceAt {
                let n=Int((now-inventory.nextChanceAt)/10800)+1
                inventory.chances=min(3,inventory.chances+n);inventory.nextChanceAt += Double(n)*10800
            }
            guard inventory.chances>0 else { throw PhysicalError.message("捞取机会还在恢复中") }
            if inventory.chances==3 { inventory.nextChanceAt=now+10800 }
            inventory.chances-=1;inventory.items.append(.init(kind:inventory.catalog.randomElement()!.id));inventory.note("从模拟放生海捞到一份惊喜")
        default: throw CompanionError.invalidState
        }
    }
}
