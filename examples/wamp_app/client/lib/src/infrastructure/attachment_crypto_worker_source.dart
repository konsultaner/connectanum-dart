const String attachmentCryptoWorkerSource = r'''
self.onmessage=async function(event){
  const data=event.data;
  const keyBytes=data.key;
  const nonce=data.nonce;
  const additionalData=data.additionalData;
  const input=data.input;
  try {
    const usage=data.operation==='encrypt'?'encrypt':'decrypt';
    const key=await crypto.subtle.importKey(
      'raw',
      keyBytes,
      {name:'AES-GCM'},
      false,
      [usage]
    );
    const result=await crypto.subtle[usage](
      {
        name:'AES-GCM',
        iv:nonce,
        additionalData:additionalData,
        tagLength:128
      },
      key,
      input
    );
    keyBytes.fill(0);
    nonce.fill(0);
    additionalData.fill(0);
    input.fill(0);
    const output=new Uint8Array(result);
    self.postMessage(output,[output.buffer]);
  }catch(_){
    keyBytes.fill(0);
    nonce.fill(0);
    additionalData.fill(0);
    input.fill(0);
    self.postMessage(null);
  }
};
''';
