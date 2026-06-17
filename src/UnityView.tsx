import React from 'react';

import NativeUnityView, { Commands } from './specs/UnityViewNativeComponent';
import type { DirectEventHandler } from 'react-native/Libraries/Types/CodegenTypes';
import { Platform } from 'react-native';

// Diagnostic timing logs (logcat: tag ReactNativeJS, content "[RNUnityTiming]").
// Set to false for production.
const DEBUG_TIMING = true;

export type UnityViewContentUpdateEvent = Readonly<{
  message: string;
}>;

export type UnityViewReadyEvent = Readonly<{}>;

export type RNUnityViewProps = {
  androidKeepPlayerMounted?: boolean;
  fullScreen?: boolean;
  onUnityMessage?: DirectEventHandler<UnityViewContentUpdateEvent>;
  onPlayerUnload?: DirectEventHandler<UnityViewContentUpdateEvent>;
  onPlayerQuit?: DirectEventHandler<UnityViewContentUpdateEvent>;
  onUnityReady?: DirectEventHandler<UnityViewReadyEvent>;
};

type ComponentRef = InstanceType<typeof NativeUnityView>;

export default class UnityView extends React.Component<RNUnityViewProps> {
  ref = React.createRef<ComponentRef>();

  public postMessage = (
    gameObject: string,
    methodName: string,
    message: string
  ) => {
    if (DEBUG_TIMING) {
      console.log(
        `[RNUnityTiming] JS postMessage ${gameObject}/${methodName} hasRef=${!!this.ref.current}`
      );
    }
    if (this.ref.current) {
      Commands.postMessage(this.ref.current, gameObject, methodName, message);
    }
  };

  public unloadUnity = () => {
    if (this.ref.current) {
      Commands.unloadUnity(this.ref.current);
    }
  };

  public pauseUnity(pause: boolean) {
    if (this.ref.current) {
      Commands.pauseUnity(this.ref.current, pause);
    }
  }

  public resumeUnity() {
    if (this.ref.current) {
      Commands.resumeUnity(this.ref.current);
    }
  }

  public windowFocusChanged(hasFocus = true) {
    if (Platform.OS !== 'android') return;

    if (this.ref.current) {
      Commands.windowFocusChanged(this.ref.current, hasFocus);
    }
  }

  private getProps() {
    return {
      ...this.props,
    };
  }

  componentDidMount() {
    if (DEBUG_TIMING) {
      console.log('[RNUnityTiming] JS UnityView mounted');
    }
  }

  componentWillUnmount() {
    if (this.ref.current) {
      Commands.unloadUnity(this.ref.current);
    }
  }

  render() {
    return <NativeUnityView ref={this.ref} {...this.getProps()} />;
  }
}
