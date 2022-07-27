%% function generates sha code for str using key and with defined algorithm
%  uses Java Cryptography MAC to generate hash.
%  MAC is an encrypted checksum generated on the underlying message that is 
%  sent along with a message to ensure message authentication.

function signStr = Message_Authentication_Code(str, key, algorithm)
    import java.net.*;
    import javax.crypto.*;
    import javax.crypto.spec.*;
    import org.apache.commons.codec.binary.*
    keyStr = java.lang.String(key);
    key = SecretKeySpec(keyStr.getBytes('UTF-8'), algorithm);
    mac = Mac.getInstance(algorithm);
    mac.init(key);
    toSignStr = java.lang.String(str);
    signStr = java.lang.String(Hex.encodeHex( mac.doFinal( toSignStr.getBytes('UTF-8'))));
end