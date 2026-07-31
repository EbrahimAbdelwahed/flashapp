import { Config } from '@remotion/cli/config';

// §4.2 / §1.4: H.264, yuv420p, 1080x1920. CRF 18 keeps the gradients clean; the blooms in
// §1.5 band badly at higher values even with the grain on top.
Config.setVideoImageFormat('jpeg');
Config.setCodec('h264');
Config.setPixelFormat('yuv420p');
Config.setCrf(18);
