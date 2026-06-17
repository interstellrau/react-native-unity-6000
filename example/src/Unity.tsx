import UnityView from '@azesmway/react-native-unity'
import React, { useRef } from 'react'
import { View } from 'react-native'

interface IMessage {
  gameObject: string
  methodName: string
  message: string
}

const Unity = () => {
  const unityRef = useRef<UnityView>(null)

  const message: IMessage = {
    gameObject: '[Scripts]',
    methodName: 'InitModule',
    message: '{"scene": "GeoPoints"}'
  }

  // Wait for the native onUnityReady event instead of a fixed setTimeout.
  // This fires as soon as Unity is actually up, so the first message is never
  // sent too early (dropped) or later than necessary.
  const handleUnityReady = () => {
    unityRef.current?.postMessage(message.gameObject, message.methodName, message.message)
  }

  return (
    // If you wrap your UnityView inside a parent, please take care to set dimensions to it (with `flex:1` for example).
    // See the `Know issues` part in the README.
    <View style={{ flex: 1 }}>
      <UnityView
        ref={unityRef}
        style={{ flex: 1 }}
        onUnityReady={handleUnityReady}
        onUnityMessage={(result) => console.log('onUnityMessage ===> ', result.nativeEvent.message)}
      />
    </View>
  )
}

export default Unity
