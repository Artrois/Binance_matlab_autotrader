classdef CipherClass < handle
    %% class to implement simple cipher functions
    % how to use:
    % secretKey = "ssshhhhhhhhhhh!!!!";
    % algorithm = "SHA-1";
    % aes = AES(secretKey, algorithm);
    % 
    % originalString = "howtodoinjava.com";
    % encryptedString = aes.encrypt(originalString);
    % decryptedString = aes.decrypt(encryptedString);
    % 
    % disp(originalString);
    % disp(encryptedString);
    % disp(decryptedString);
    properties (Access = private)
        secretKey
        cipher
    end
    
    methods 
        
        %% creates according instances for encryption/decryption
        %  inputs:
        %       secret: STRING secret key used for encryption/decryption
        %       algorithm: STRING with algorithm that is supported by
        %       MessageDigest class. Supported algorithms are:
        %       MD2, MD5, SHA-1, SHA-256, SHA-384, SHA-512
        %       if no algorithm set, SHA-1 will be used
        function self = CipherClass(secret, algorithm)
            %AES Construct an instance of this class
            %   algorithm options are https://docs.oracle.com/javase/9/docs/specs/security/standard-names.html#messagedigest-algorithms
            import java.security.MessageDigest;
            import java.lang.String;
            import java.util.Arrays;
            import javax.crypto.Cipher;
            
            switch nargin  
                case 0
                    error('CipherClass::AES():no parameters set->exit');
                    return;
                case 1
                    algorithm = "SHA-1";
                otherwise
                    error('CipherClass::AES():too many parameters->exit');
                    return;
            end
                        
            
            key = String(secret).getBytes("UTF-8");
            sha = MessageDigest.getInstance(algorithm);
            key = sha.digest(key);
            key = Arrays.copyOf(key, 16);
            self.secretKey = javaObject('javax.crypto.spec.SecretKeySpec',key, "AES");
            self.cipher = Cipher.getInstance("AES/ECB/PKCS5Padding");
        end
        
        function encrypted = encrypt(self, strToEncrypt)
            %ENCRYPT Summary of this method goes here
            %   Detailed explanation goes here           
            import java.util.Base64;
            import java.lang.String;
            import javax.crypto.Cipher;
            
            self.cipher.init(Cipher.ENCRYPT_MODE, self.secretKey);
            encrypted = string(Base64.getEncoder().encodeToString(self.cipher.doFinal(String(strToEncrypt).getBytes("UTF-8"))));
        end
        
        function encrypted = encryptStructuredData(self, structuredData)
            encrypted = self.encrypt(jsonencode(structuredData));
        end
        
        function decrypted = decryptStructuredData(self, encryptedStructuredData)
            decrypted = jsondecode(self.decrypt(encryptedStructuredData));
        end        
        
        function decrypted = decrypt(self, strToDecrypt)
            %DECRYPT Summary of this method goes here
            %   Detailed explanation goes here
            import javax.crypto.Cipher;
            import java.lang.String;
            import java.util.Base64;
            
            self.cipher.init(Cipher.DECRYPT_MODE, self.secretKey);
            %decrypted = string(String(self.cipher.doFinal(Base64.getDecoder().decode(strToDecrypt))));
            decrypted = char(String(self.cipher.doFinal(Base64.getDecoder().decode(strToDecrypt))));
        end
        
        %% generates key pair based on RSA
        function [public_key_bytestring, private_key_bytestring] = genKeyPair(self)
            import java.security.KeyPair;
            import java.security.KeyPairGenerator;
            import java.security.Signature;

            import javax.crypto.BadPaddingException;
            import javax.crypto.Cipher;
            import org.apache.commons.codec.binary.*
            
            % Creating KeyPair generator object
            keyPairGen = KeyPairGenerator.getInstance("RSA");

            % Initializing the key pair generator
            keyPairGen.initialize(512);% 2048bits default, min 512bits

            % Generating the pair of keys
            pair = keyPairGen.generateKeyPair();
            public_key_bytestring = java.lang.String(Hex.encodeHex(pair.getPublic().getEncoded()));
            private_key_bytestring = java.lang.String(Hex.encodeHex(pair.getPrivate().getEncoded()));
            %SecretKeySpec
        end
        

    end
end

