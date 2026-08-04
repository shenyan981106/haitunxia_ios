/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { MethodCall, MethodCallHandler, MethodChannel, MethodResult, } from '@ohos/flutter_ohos';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { VideoPlayerApi } from './VideoPlayerApi';
import { VideoPlayerApiImpl } from './VideoPlayerApiImpl';
import fs from '@ohos.file.fs';

const TAG: string = "VideoPlayerPlugin";
export class VideoPlayerPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private pluginBinding: FlutterPluginBinding | null = null;
  private videoPlayerApi: VideoPlayerApiImpl | null = null;
  private flutterState: FlutterState | null = null;
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method == "getFileFdByPath") {
      try {
        let filePath = call.argument("filePath") as string
        Log.i(TAG, 'filePath: ' + filePath);
        let openFile: fs.File = fs.openSync(filePath);
        result.success(openFile.fd)
      } catch (e) {
        Log.e(TAG, 'getFileFdByPath failed with err: ' + e);
        result.success(-1)
      }

    }
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    Log.i(TAG, "VideoPlayer onAttachedToEngine");
    this.flutterState = new FlutterState(this.pluginBinding.getBinaryMessenger(), this.pluginBinding.getTextureRegistry());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = null;
    if (this.videoPlayerApi != null) {
      this.videoPlayerApi.detach();
      this.videoPlayerApi = null;
    }
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    Log.i(TAG, "VideoPlayer onAttachedToAbility");
    if (this.flutterState != null && this.pluginBinding != null && this.videoPlayerApi == null) {
      this.videoPlayerApi = new VideoPlayerApiImpl(this.flutterState, binding);
      this.videoPlayerApi.setup(this.pluginBinding.getBinaryMessenger());
    }
    this.channel = new MethodChannel(this.pluginBinding!.getBinaryMessenger(), "plugins.flutter.io/video_player_ohos");
    this.channel.setMethodCallHandler(this)
  }
  onDetachedFromAbility(): void {
    this.videoPlayerApi = null;
  }
}

export class FlutterState {
  private binaryMessenger: BinaryMessenger;
  private textureRegistry: TextureRegistry;

  constructor(binaryMessenger: BinaryMessenger, textureRegistry: TextureRegistry) {
    this.binaryMessenger = binaryMessenger;
    this.textureRegistry = textureRegistry;
  }

  getBinaryMessenger(): BinaryMessenger {
    return this.binaryMessenger;
  }

  getTextureRegistry(): TextureRegistry {
    return this.textureRegistry;
  }
}