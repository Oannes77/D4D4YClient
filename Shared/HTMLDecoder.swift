import Foundation

/// 网络层与字符编码的解耦点。
///
/// 职责边界：
/// - `HTTPClient` 只负责收发字节（`Data`）；
/// - `HTMLDecoder` 只负责 `Data -> String`；
/// - `Parser` 只接收 `String`，不关心编码。
///
/// 站点声明 `charset=gbk`。解码策略：
/// 1. 先试严格 UTF-8（某些 CDN / 代理可能已转码，且 Cloudflare 质询页本身是 UTF-8）。
///    仅当结果真含 "<" 才认定像 HTML，避免把二进制误判为成功。
/// 2. 失败退回 GB18030——GBK 的超集，覆盖 GBK 全部字符，避免生僻字丢失。
enum HTMLDecoder {

    /// 站点声明的字符编码名（用于日志 / 诊断）。
    static let declaredCharset = "gbk"

    /// 把响应体解码为 String。连 GB18030 都无法解读时返回 nil，由调用方抛 `textEncodingFailed`。
    static func decode(_ data: Data) -> String? {
        // 1) 严格 UTF-8
        if let utf8 = String(data: data, encoding: .utf8), utf8.contains("<") {
            return utf8
        }
        // 2) 退回 GB18030（GBK 超集）
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb18030)
    }
}
