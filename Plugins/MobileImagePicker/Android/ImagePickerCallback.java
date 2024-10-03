package com.binouze;

public interface ImagePickerCallback
{
    public void onUrlPicked(String url);
    public void onMultipleUrlsPicked(String[] urls);
}
